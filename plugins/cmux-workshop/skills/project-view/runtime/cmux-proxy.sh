#!/bin/bash
# cmux Socket Proxy — 통합 운영 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_PY="$SCRIPT_DIR/proxy.py"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
LOG_FILE="/tmp/cmux-proxy.log"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.cmux.socket-proxy.plist"

# ── 소켓 경로 감지 ──

detect_socket_path() {
    local json
    json=$(cmux identify --json 2>/dev/null) || {
        echo "ERROR: cmux identify --json 실패" >&2
        exit 1
    }
    python3 -c "import json,sys; print(json.loads(sys.stdin.read())['socket_path'])" <<< "$json"
}

get_listen_path() {
    detect_socket_path
}

get_upstream_path() {
    local listen_path
    listen_path="$(detect_socket_path)"
    echo "$(dirname "$listen_path")/cmux-real.sock"
}

get_pid_file() {
    echo "/tmp/cmux-proxy.pid"
}

# ── 검증 헬퍼 ──

check_redis() {
    if ! redis-cli ping >/dev/null 2>&1; then
        echo "ERROR: Redis 서버가 실행 중이지 않습니다" >&2
        echo "  → brew services start redis" >&2
        exit 1
    fi
}

check_python_redis() {
    if ! python3 -c "import redis" 2>/dev/null; then
        echo "ERROR: Python redis 패키지가 설치되지 않았습니다" >&2
        echo "  → pip3 install redis>=5.0.0" >&2
        exit 1
    fi
}

check_cmux_running() {
    ps aux | grep "[/]Applications/cmux.app/Contents/MacOS/cmux" >/dev/null 2>&1 || return 1
}

get_cmux_pid() {
    ps aux | grep "[/]Applications/cmux.app/Contents/MacOS/cmux" | awk '{print $2}' | head -1
}

check_proxy_running() {
    local pid_file
    pid_file="$(get_pid_file)"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$pid_file"
    fi
    return 1
}

test_socket() {
    local sock_path="$1"
    python3 -c "
import socket, sys, json
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.settimeout(3)
    s.connect(sys.argv[1])
    s.sendall(b'{\"id\":\"health\",\"method\":\"system.ping\",\"params\":{}}\n')
    data = b''
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
        if b'\n' in data:
            break
    resp = json.loads(data.strip())
    sys.exit(0 if resp.get('ok') else 1)
except Exception:
    sys.exit(1)
finally:
    s.close()
" "$sock_path" 2>/dev/null
}

# ── 명령: inject (방법 A) ──

cmd_inject() {
    local LISTEN_PATH UPSTREAM_PATH PID_FILE

    LISTEN_PATH="$(get_listen_path)"
    UPSTREAM_PATH="$(get_upstream_path)"
    PID_FILE="$(get_pid_file)"

    echo "━━━ cmux Socket Proxy: inject ━━━"
    echo ""

    # 사전 검증
    check_redis
    check_python_redis

    if check_proxy_running; then
        echo "ERROR: 프록시가 이미 실행 중입니다"
        cmd_status
        exit 1
    fi

    if ! check_cmux_running; then
        echo "ERROR: cmux 앱이 실행 중이지 않습니다"
        exit 1
    fi

    if [ ! -S "$LISTEN_PATH" ]; then
        echo "ERROR: 소켓 파일 없음: $LISTEN_PATH"
        exit 1
    fi

    # 소켓 교체
    echo "  소켓 이동: $LISTEN_PATH → $UPSTREAM_PATH"
    mv "$LISTEN_PATH" "$UPSTREAM_PATH"

    # cmux 앱 응답 확인
    echo "  upstream 소켓 테스트..."
    if ! test_socket "$UPSTREAM_PATH"; then
        echo "ERROR: cmux 앱이 이동된 소켓에서 응답하지 않음, 원복 중..."
        mv "$UPSTREAM_PATH" "$LISTEN_PATH"
        exit 1
    fi
    echo "  → upstream 정상 ✓"

    # 프록시 시작
    echo "  프록시 시작..."
    nohup python3 "$PROXY_PY" \
        --listen "$LISTEN_PATH" \
        --upstream "$UPSTREAM_PATH" \
        >> "$LOG_FILE" 2>&1 &
    local PROXY_PID=$!
    echo "$PROXY_PID" > "$PID_FILE"

    sleep 0.8

    # 프로세스 생존 확인
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "ERROR: 프록시 시작 실패, 소켓 원복 중..."
        mv "$UPSTREAM_PATH" "$LISTEN_PATH"
        rm -f "$PID_FILE"
        echo "  → 최근 로그:"
        tail -5 "$LOG_FILE" 2>/dev/null || true
        exit 1
    fi

    # 전체 파이프라인 확인
    echo "  프록시 소켓 테스트..."
    if ! test_socket "$LISTEN_PATH"; then
        echo "ERROR: 프록시가 응답하지 않음, 정리 중..."
        kill "$PROXY_PID" 2>/dev/null || true
        sleep 0.5
        mv "$UPSTREAM_PATH" "$LISTEN_PATH"
        rm -f "$PID_FILE"
        exit 1
    fi

    echo ""
    echo "  ✓ 프록시 시작 완료 (PID: $PROXY_PID)"
    echo "    Listen:   $LISTEN_PATH"
    echo "    Upstream: $UPSTREAM_PATH"
    echo "    로그:     $LOG_FILE"
}

# ── 명령: restart-app (방법 B) ──

cmd_restart_app() {
    local LISTEN_PATH UPSTREAM_PATH PID_FILE

    LISTEN_PATH="$(get_listen_path)"
    UPSTREAM_PATH="$(get_upstream_path)"
    PID_FILE="$(get_pid_file)"

    echo "━━━ cmux Socket Proxy: restart-app ━━━"
    echo ""

    check_redis
    check_python_redis

    if check_proxy_running; then
        echo "ERROR: 프록시가 이미 실행 중입니다. 먼저 stop 하세요."
        exit 1
    fi

    # cmux 앱 종료
    echo "  cmux 앱 종료 중..."
    osascript -e 'tell application "cmux" to quit' 2>/dev/null || true
    sleep 2
    if pgrep -x cmux >/dev/null 2>&1; then
        echo "  → 강제 종료..."
        pkill -x cmux 2>/dev/null || true
        sleep 1
    fi
    echo "  → cmux 앱 종료 완료"

    # 소켓 파일 정리
    rm -f "$LISTEN_PATH" "$UPSTREAM_PATH"

    # 프록시 먼저 시작
    echo "  프록시 시작..."
    nohup python3 "$PROXY_PY" \
        --listen "$LISTEN_PATH" \
        --upstream "$UPSTREAM_PATH" \
        >> "$LOG_FILE" 2>&1 &
    local PROXY_PID=$!
    echo "$PROXY_PID" > "$PID_FILE"
    sleep 0.5

    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "ERROR: 프록시 시작 실패"
        rm -f "$PID_FILE"
        tail -5 "$LOG_FILE" 2>/dev/null || true
        exit 1
    fi
    echo "  → 프록시 시작 완료 (PID: $PROXY_PID)"

    # cmux 앱 재시작 (환경변수로 소켓 경로 지정)
    echo "  cmux 앱 재시작 (CMUX_SOCKET_PATH=$UPSTREAM_PATH)..."
    CMUX_SOCKET_PATH="$UPSTREAM_PATH" open -a cmux

    # upstream 소켓 생성 대기
    echo "  upstream 소켓 대기 중..."
    local waited=0
    while [ ! -S "$UPSTREAM_PATH" ] && [ "$waited" -lt 30 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done

    if [ ! -S "$UPSTREAM_PATH" ]; then
        echo "ERROR: cmux 앱이 15초 내에 소켓을 생성하지 않음"
        echo "  → 프록시 종료 중..."
        kill "$PROXY_PID" 2>/dev/null || true
        rm -f "$PID_FILE"
        exit 1
    fi

    sleep 0.5

    # 전체 파이프라인 확인
    echo "  연결 테스트..."
    if test_socket "$LISTEN_PATH"; then
        echo ""
        echo "  ✓ restart-app 완료"
        echo "    Listen:   $LISTEN_PATH"
        echo "    Upstream: $UPSTREAM_PATH"
        echo "    프록시 PID: $PROXY_PID"
        echo "    로그: $LOG_FILE"
    else
        echo "WARNING: 프록시 시작됨, 하지만 연결 테스트 실패"
        echo "  → 로그 확인: tail -20 $LOG_FILE"
    fi
}

# ── 명령: install (방법 C) ──

cmd_install() {
    local LISTEN_PATH UPSTREAM_PATH

    LISTEN_PATH="$(get_listen_path)"
    UPSTREAM_PATH="$(get_upstream_path)"

    echo "━━━ cmux Socket Proxy: install (LaunchAgent) ━━━"
    echo ""

    check_redis
    check_python_redis

    # LaunchAgent plist 생성
    mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"
    cat > "$LAUNCH_AGENT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cmux.socket-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which python3)</string>
        <string>$PROXY_PY</string>
        <string>--listen</string>
        <string>$LISTEN_PATH</string>
        <string>--upstream</string>
        <string>$UPSTREAM_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
PLIST

    echo "  LaunchAgent plist 생성: $LAUNCH_AGENT_PLIST"

    # 로드
    launchctl load "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    echo "  LaunchAgent 로드 완료"

    echo ""
    echo "  ✓ LaunchAgent 설치 완료"
    echo ""
    echo "  cmux 앱의 소켓 경로를 변경해야 합니다 (택 1):"
    echo "    a) 즉시 적용: ./cmux-proxy.sh restart-app"
    echo "    b) defaults write: defaults write ai.manaflow.cmuxterm LSEnvironment -dict-add CMUX_SOCKET_PATH '$UPSTREAM_PATH'"
    echo "    c) 수동: CMUX_SOCKET_PATH='$UPSTREAM_PATH' open -a cmux"
}

# ── 명령: uninstall ──

cmd_uninstall() {
    echo "━━━ cmux Socket Proxy: uninstall ━━━"
    echo ""

    # LaunchAgent 제거
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PLIST"
        echo "  LaunchAgent 제거 완료"
    else
        echo "  LaunchAgent가 설치되지 않았습니다"
    fi

    # 프록시 종료
    cmd_stop 2>/dev/null || true

    echo ""
    echo "  ✓ 제거 완료"
    echo "  → defaults delete ai.manaflow.cmuxterm LSEnvironment (설정한 경우)"
    echo "  → cmux 앱을 재시작하세요"
}

# ── 명령: stop ──

cmd_stop() {
    local LISTEN_PATH UPSTREAM_PATH PID_FILE

    LISTEN_PATH="$(get_listen_path)"
    UPSTREAM_PATH="$(get_upstream_path)"
    PID_FILE="$(get_pid_file)"

    echo "━━━ cmux Socket Proxy: stop ━━━"
    echo ""

    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  프록시 종료 중 (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                echo "  → 강제 종료..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            echo "  → 프록시 종료 완료"
        else
            echo "  프록시 프로세스 없음 (PID: $pid, 이미 종료됨)"
        fi
        rm -f "$PID_FILE"
    else
        echo "  PID 파일 없음 (프록시가 실행 중이지 않은 것으로 보임)"
    fi

    # 소켓 원복 (inject 모드)
    if [ -S "$UPSTREAM_PATH" ] && [ ! -S "$LISTEN_PATH" ]; then
        echo "  소켓 원복: $UPSTREAM_PATH → $LISTEN_PATH"
        mv "$UPSTREAM_PATH" "$LISTEN_PATH"
    fi

    # 프록시 소켓 정리
    if [ -S "$LISTEN_PATH" ]; then
        # listen_path가 프록시 소켓인지 확인
        if ! test_socket "$LISTEN_PATH" 2>/dev/null; then
            rm -f "$LISTEN_PATH"
            echo "  스태일 프록시 소켓 제거: $LISTEN_PATH"
        fi
    fi

    echo ""
    echo "  ✓ 정리 완료"
}

# ── 명령: status ──

cmd_status() {
    local LISTEN_PATH UPSTREAM_PATH PID_FILE

    LISTEN_PATH="$(get_listen_path)"
    UPSTREAM_PATH="$(get_upstream_path)"
    PID_FILE="$(get_pid_file)"

    echo "━━━ cmux Socket Proxy 상태 ━━━"
    echo ""

    # cmux 앱
    if check_cmux_running; then
        local cmux_pid
        cmux_pid=$(get_cmux_pid)
        echo "  cmux 앱      : 실행 중 (PID: $cmux_pid)"
    else
        echo "  cmux 앱      : 실행 중 아님"
    fi

    # 프록시
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  프록시        : 실행 중 (PID: $pid)"
        else
            echo "  프록시        : 종료됨 (PID 파일 잔존: $pid)"
        fi
    else
        echo "  프록시        : 실행 중 아님"
    fi

    echo ""
    echo "  소켓 상태:"
    if [ -S "$LISTEN_PATH" ]; then
        echo "    $LISTEN_PATH : 존재"
    else
        echo "    $LISTEN_PATH : 없음"
    fi
    if [ -S "$UPSTREAM_PATH" ]; then
        echo "    $UPSTREAM_PATH : 존재 (upstream)"
    else
        echo "    $UPSTREAM_PATH : 없음"
    fi

    echo ""
    echo "  Redis:"
    if redis-cli ping >/dev/null 2>&1; then
        echo "    서버         : 실행 중"
        local req_len res_len
        req_len=$(redis-cli XLEN cmux:requests 2>/dev/null || echo "?")
        res_len=$(redis-cli XLEN cmux:responses 2>/dev/null || echo "?")
        local term_len
        term_len=$(redis-cli XLEN cmux:terminal_output 2>/dev/null || echo "?")
        echo "    cmux:requests        : $req_len entries"
        echo "    cmux:responses       : $res_len entries"
        echo "    cmux:terminal_output : $term_len entries"
    else
        echo "    서버         : 실행 중 아님"
    fi

    # LaunchAgent
    echo ""
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        echo "  LaunchAgent  : 설치됨"
    else
        echo "  LaunchAgent  : 설치 안됨"
    fi

    # 로그
    echo ""
    if [ -f "$LOG_FILE" ]; then
        local log_size
        log_size=$(du -h "$LOG_FILE" | cut -f1)
        echo "  로그 파일    : $LOG_FILE ($log_size)"
        echo "  최근 로그:"
        tail -3 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    else
        echo "  로그 파일    : 없음"
    fi
}

# ── 명령: monitor ──

cmd_monitor() {
    shift_args="${*:2}"
    python3 "$MONITOR_PY" $shift_args
}

# ── 사용법 ──

usage() {
    echo "사용법: $(basename "$0") <명령>"
    echo ""
    echo "명령:"
    echo "  inject       실행 중 소켓 즉시 교체 (방법 A, 앱 재시작 불필요)"
    echo "  restart-app  환경변수와 함께 앱 재시작 (방법 B)"
    echo "  install      LaunchAgent 자동화 설치 (방법 C)"
    echo "  uninstall    LaunchAgent 제거 및 원복"
    echo "  stop         프록시 종료 및 소켓 원복"
    echo "  status       전체 상태 확인"
    echo "  monitor      실시간 트래픽 모니터 실행"
    exit 1
}

# ── 메인 ──

case "${1:-}" in
    inject)      cmd_inject ;;
    restart-app) cmd_restart_app ;;
    install)     cmd_install ;;
    uninstall)   cmd_uninstall ;;
    stop)        cmd_stop ;;
    status)      cmd_status ;;
    monitor)     cmd_monitor "$@" ;;
    *)           usage ;;
esac
