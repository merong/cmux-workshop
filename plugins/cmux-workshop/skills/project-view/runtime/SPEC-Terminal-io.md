# cmux 터미널 I/O 모니터링 — 추가 명세

> SPEC.md 15장으로 추가

---

## 15. 터미널 I/O 모니터링

### 15.1 문제 정의

cmux의 소켓 API(`/tmp/cmux.sock`)는 **제어 평면(Control Plane)**이다.
터미널의 실제 입출력은 **데이터 평면(Data Plane)**인 PTY를 통해 직접 흐르며 소켓을 거치지 않는다.

```
데이터 평면 (PTY):
  사용자 키보드 → macOS event → AppKit → libghostty → PTY master (write) → shell
  shell stdout → PTY master (read) → libghostty → GPU render → 화면

제어 평면 (Socket):
  cmux CLI → /tmp/cmux.sock → TerminalController (Swift)
  → surface.send_text: PTY에 텍스트 주입 (입력 방향)
  → surface.read_text: libghostty의 화면 버퍼 스냅샷 (출력 방향, 폴링)
```

따라서 소켓 프록시만으로는 사용자의 실제 키 입력이나 프로그램 출력 스트림을 캡처할 수 없다.

### 15.2 cmux 소켓 API에서 사용 가능한 터미널 데이터

| API | CLI 명령 | 방향 | 실시간 | 설명 |
|-----|---------|------|--------|------|
| `surface.send_text` | `cmux send` | 입력 주입 | 명령 시점 | 소켓을 통해 PTY에 텍스트 쓰기 |
| `surface.send_key` | `cmux send-key` | 입력 주입 | 명령 시점 | 소켓을 통해 키 이벤트 전달 |
| `surface.read_text` | `cmux read-screen --lines N` | 출력 읽기 | 폴링(스냅샷) | 현재 화면 버퍼의 텍스트 추출 |

미구현 (cmux issue #153, tmux parity):
- `pipe-pane`: 패널 출력을 셸 명령으로 실시간 스트리밍 → 미구현
- `capture-pane` 이벤트 구독: 화면 변경 시 push → 미구현

### 15.3 방법 1: read-screen 폴링 기반 모니터링

#### 개요
`cmux read-screen`을 주기적으로 호출하여 화면 변화를 감지하고 Redis에 적재한다.
가장 간단하며 cmux 앱 수정 없이 즉시 사용 가능하다.

#### 동작 방식

```
polling_monitor.py:

1. cmux list-surfaces로 모니터링 대상 surface 목록 획득
2. 각 surface에 대해 interval(기본 1초)마다:
   a) cmux read-screen --surface <id> --lines 80 호출 (소켓 또는 CLI)
   b) 이전 스냅샷과 diff 비교
   c) 변경된 줄만 Redis Stream에 적재
3. diff 알고리즘: 단순 해시 비교 (줄 단위)
   - 변경 없으면 skip (Redis 부하 최소화)
   - 변경 시 changed_lines, full_snapshot 모두 기록
```

#### Redis Stream 엔트리 (cmux:terminal_output)

| 필드 | 타입 | 설명 |
|------|------|------|
| `surface_id` | string | 대상 surface ID |
| `workspace_id` | string | 워크스페이스 ID |
| `ts` | string | 타임스탬프 (Unix ms) |
| `event` | string | `"screen_changed"` 또는 `"screen_snapshot"` |
| `changed_lines` | string | 변경된 줄 번호 목록 (JSON array) |
| `diff` | string | 변경된 줄 내용 (JSON: {line_no: text}) |
| `full_text` | string | 전체 화면 텍스트 (선택적, 주기적) |
| `line_count` | string | 읽은 총 줄 수 |

#### 구현 명세

```python
# polling_monitor.py 핵심 로직

import asyncio
import hashlib
import json
import subprocess

class ScreenPoller:
    def __init__(self, surface_id, interval=1.0):
        self.surface_id = surface_id
        self.interval = interval
        self.prev_lines = []      # 이전 스냅샷 (줄 단위 리스트)
        self.prev_hash = ""       # 전체 해시 (빠른 변경 감지)

    async def poll_once(self) -> dict | None:
        """한 번 폴링하여 변경 시 diff 반환"""

        # 소켓 직접 호출 (CLI보다 빠름)
        text = await self._read_screen()
        current_lines = text.split('\n')
        current_hash = hashlib.md5(text.encode()).hexdigest()

        # 변경 없으면 skip
        if current_hash == self.prev_hash:
            return None

        # diff 계산
        changed = {}
        max_len = max(len(current_lines), len(self.prev_lines))
        for i in range(max_len):
            curr = current_lines[i] if i < len(current_lines) else ""
            prev = self.prev_lines[i] if i < len(self.prev_lines) else ""
            if curr != prev:
                changed[str(i)] = curr

        self.prev_lines = current_lines
        self.prev_hash = current_hash

        return {
            "surface_id": self.surface_id,
            "event": "screen_changed",
            "changed_lines": json.dumps(list(changed.keys())),
            "diff": json.dumps(changed, ensure_ascii=False),
            "line_count": str(len(current_lines)),
        }

    async def _read_screen(self) -> str:
        """cmux 소켓 API로 화면 텍스트 읽기"""
        # JSON-RPC 직접 호출
        request = json.dumps({
            "id": "poll",
            "method": "surface.read_text",
            "params": {
                "surface_id": self.surface_id,
                "scrollback": False,
                "lines": 80,
            }
        })
        # Unix socket 연결하여 전송/수신
        reader, writer = await asyncio.open_unix_connection("/tmp/cmux.sock")
        writer.write(request.encode() + b'\n')
        await writer.drain()
        response = await reader.readline()
        writer.close()

        data = json.loads(response.decode())
        return data.get("result", {}).get("text", "")
```

#### CLI 사용법

```bash
# 단일 surface 모니터링
python3 polling_monitor.py --surface surface:1

# 모든 surface 자동 감지
python3 polling_monitor.py --all

# 빠른 폴링 (0.5초)
python3 polling_monitor.py --surface surface:1 --interval 0.5

# 특정 워크스페이스만
python3 polling_monitor.py --workspace workspace:2

# 전체 스냅샷도 주기적 저장 (10초마다)
python3 polling_monitor.py --surface surface:1 --snapshot-interval 10
```

#### 한계

- 폴링 간격(기본 1초) 사이의 출력은 누락 가능 (빠른 스크롤, 순간적 에러 메시지 등)
- `read-screen`은 현재 보이는 화면만 반환 (스크롤백 전체를 반복 읽으면 성능 저하)
- 각 폴링마다 소켓 연결 1회 소비 (많은 surface를 짧은 간격으로 폴링하면 부하)
- 사용자의 키보드 입력은 캡처 불가 (출력 변화만 감지)


### 15.4 방법 2: script 명령 래핑 (세션 전체 기록)

#### 개요
macOS 내장 `script` 명령으로 PTY 세션의 전체 I/O를 파일로 기록한다.
cmux에서 새 워크스페이스/터미널을 열 때 `script`로 래핑하여 실행한다.

#### 동작 방식

```
1. cmux 워크스페이스 생성 시 script 명령으로 셸 래핑:
   cmux new-workspace --command "script -F /tmp/cmux-session-$(date +%s).log"

2. script 명령이 PTY를 하나 더 생성하여 모든 I/O를 파일로 기록:
   cmux PTY → script PTY → shell
   
3. tail -f로 로그 파일을 읽어 Redis에 스트리밍:
   tail -F /tmp/cmux-session-*.log | python3 stream_to_redis.py

구조:
   ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌───────┐
   │  cmux   │ ──► │ script  │ ──► │  PTY    │ ──► │ shell │
   │  PTY    │     │ (기록)   │     │ (내부)   │     │       │
   └─────────┘     └────┬────┘     └─────────┘     └───────┘
                        │
                        ▼
                   /tmp/cmux-session-xxx.log
                        │
                        ▼
                   tail -F → stream_to_redis.py → Redis Stream
```

#### 셸 래퍼 스크립트 (cmux-record.sh)

```bash
#!/usr/bin/env bash
# cmux 터미널 세션 기록 래퍼
# Usage: cmux new-workspace --command "/path/to/cmux-record.sh"

SESSION_DIR="/tmp/cmux-sessions"
mkdir -p "$SESSION_DIR"

SESSION_ID="${CMUX_SURFACE_ID:-$(date +%s)}"
LOG_FILE="${SESSION_DIR}/session-${SESSION_ID}.log"
TIMING_FILE="${SESSION_DIR}/session-${SESSION_ID}.timing"

echo "Recording to: $LOG_FILE"

# -F: 즉시 플러시 (macOS)
# -q: 시작/종료 메시지 억제
exec script -F -q "$LOG_FILE" "$SHELL"
```

#### stream_to_redis.py (파일 → Redis 스트리머)

```python
# 핵심 로직
import asyncio
import os
import redis.asyncio as aioredis

async def stream_file_to_redis(log_path, surface_id, redis_url):
    r = aioredis.from_url(redis_url, decode_responses=True)

    # tail -F 동등 구현
    with open(log_path, 'r', errors='replace') as f:
        # 파일 끝으로 이동
        f.seek(0, os.SEEK_END)

        while True:
            line = f.readline()
            if line:
                await r.xadd("cmux:terminal_io", {
                    "surface_id": surface_id,
                    "ts": str(int(time.time() * 1000)),
                    "direction": "output",       # script는 출력만 기록
                    "data": line.rstrip('\n'),
                    "source": "script",
                }, maxlen=50000, approximate=True)
            else:
                await asyncio.sleep(0.05)  # 50ms 대기
```

#### 한계

- 각 워크스페이스를 `script`로 래핑해야 함 (자동화 가능하지만 수동 개입 필요)
- `script` 출력에 ANSI 이스케이프 시퀀스 포함 (파싱 필요)
- 사용자의 키보드 입력은 에코된 형태로만 보임 (패스워드 입력 등 non-echo 입력은 보이지 않음)
- 기존에 이미 열려있는 워크스페이스에는 적용 불가


### 15.5 방법 3: PTY 프록시 (실시간, 양방향)

#### 개요
cmux가 셸을 실행할 때 사용하는 셸 경로를 PTY 프록시로 교체한다.
프록시가 실제 셸을 자식 프로세스로 실행하면서 양방향 I/O를 캡처한다.

#### 동작 방식

```
정상 경로:
  cmux → PTY → /bin/zsh

프록시 적용:
  cmux → PTY → pty-proxy (사용자 셸로 위장) → PTY2 → /bin/zsh
                    │
                    ├─ stdin 캡처  → Redis (cmux:terminal_input)
                    └─ stdout 캡처 → Redis (cmux:terminal_output)
```

#### 셸 프록시 구현 (pty_proxy.py)

```python
#!/usr/bin/env python3
"""
PTY 프록시 — cmux의 셸 경로를 교체하여 터미널 I/O를 캡처

cmux 설정:
  ghostty config에서 shell 경로를 이 프록시로 변경:
  ~/.config/ghostty/config:
    command = /path/to/pty_proxy.py

  또는 cmux new-workspace --command "/path/to/pty_proxy.py"
"""

import asyncio
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

import redis

REAL_SHELL = os.environ.get("CMUX_REAL_SHELL", os.environ.get("SHELL", "/bin/zsh"))
REDIS_URL = os.environ.get("CMUX_PROXY_REDIS_URL", "redis://localhost:6379/0")
SURFACE_ID = os.environ.get("CMUX_SURFACE_ID", "unknown")
WORKSPACE_ID = os.environ.get("CMUX_WORKSPACE_ID", "unknown")
STREAM_INPUT = "cmux:terminal_input"
STREAM_OUTPUT = "cmux:terminal_output"
MAXLEN = 50000

def main():
    r = redis.from_url(REDIS_URL, decode_responses=False)

    # 자식 프로세스로 실제 셸 실행 (새 PTY 할당)
    child_pid, master_fd = pty.fork()

    if child_pid == 0:
        # 자식: 실제 셸 실행
        os.execvp(REAL_SHELL, [REAL_SHELL, "-l"])
        # execvp 실패 시
        sys.exit(1)

    # 부모: 프록시 역할

    # 터미널 크기 동기화
    def sync_winsize(signum=None, frame=None):
        try:
            winsize = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b'\x00' * 8)
            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
        except OSError:
            pass

    signal.signal(signal.SIGWINCH, sync_winsize)
    sync_winsize()

    # stdin을 raw 모드로 전환
    old_settings = termios.tcgetattr(sys.stdin.fileno())
    try:
        import tty
        tty.setraw(sys.stdin.fileno())

        session_id = f"{int(time.time() * 1000)}-{os.getpid()}"
        buffer_size = 4096

        while True:
            rlist, _, _ = select.select([sys.stdin.fileno(), master_fd], [], [], 0.1)

            for fd in rlist:
                if fd == sys.stdin.fileno():
                    # 사용자 입력 → 셸로 전달 + Redis 기록
                    data = os.read(fd, buffer_size)
                    if not data:
                        return

                    os.write(master_fd, data)  # 셸로 전달

                    # Redis에 입력 기록
                    try:
                        r.xadd(STREAM_INPUT, {
                            b"session_id": session_id.encode(),
                            b"surface_id": SURFACE_ID.encode(),
                            b"workspace_id": WORKSPACE_ID.encode(),
                            b"ts": str(int(time.time() * 1000)).encode(),
                            b"direction": b"input",
                            b"data": data,  # raw bytes (제어 문자 포함)
                            b"size": str(len(data)).encode(),
                        }, maxlen=MAXLEN, approximate=True)
                    except Exception:
                        pass  # Redis 실패해도 셸은 계속

                elif fd == master_fd:
                    # 셸 출력 → 사용자 화면에 표시 + Redis 기록
                    try:
                        data = os.read(fd, buffer_size)
                    except OSError:
                        return  # 셸 종료

                    if not data:
                        return

                    os.write(sys.stdout.fileno(), data)  # 화면에 출력

                    # Redis에 출력 기록
                    try:
                        r.xadd(STREAM_OUTPUT, {
                            b"session_id": session_id.encode(),
                            b"surface_id": SURFACE_ID.encode(),
                            b"workspace_id": WORKSPACE_ID.encode(),
                            b"ts": str(int(time.time() * 1000)).encode(),
                            b"direction": b"output",
                            b"data": data,  # raw bytes (ANSI 시퀀스 포함)
                            b"size": str(len(data)).encode(),
                        }, maxlen=MAXLEN, approximate=True)
                    except Exception:
                        pass

    except (IOError, OSError):
        pass
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_settings)
        os.waitpid(child_pid, 0)

if __name__ == "__main__":
    main()
```

#### Ghostty 설정으로 적용

cmux는 Ghostty 설정 파일(`~/.config/ghostty/config`)을 읽으므로, 여기서 셸 경로를 프록시로 교체:

```
# ~/.config/ghostty/config

# 기존
# command = /bin/zsh

# 프록시 적용 (CMUX_REAL_SHELL 환경변수로 실제 셸 지정)
command = /path/to/pty_proxy.py
```

또는 cmux 워크스페이스 생성 시 개별 적용:

```bash
CMUX_REAL_SHELL=/bin/zsh cmux new-workspace --command "/path/to/pty_proxy.py"
```

#### Redis Stream 엔트리

입력 스트림 (cmux:terminal_input):

| 필드 | 타입 | 설명 |
|------|------|------|
| `session_id` | string | 세션 고유 ID |
| `surface_id` | string | cmux surface ID |
| `workspace_id` | string | cmux workspace ID |
| `ts` | string | 타임스탬프 (Unix ms) |
| `direction` | string | `"input"` |
| `data` | bytes | raw 입력 바이트 (제어 문자 포함) |
| `size` | string | 데이터 크기 |

출력 스트림 (cmux:terminal_output):

| 필드 | 타입 | 설명 |
|------|------|------|
| `session_id` | string | 세션 고유 ID |
| `surface_id` | string | cmux surface ID |
| `workspace_id` | string | cmux workspace ID |
| `ts` | string | 타임스탬프 (Unix ms) |
| `direction` | string | `"output"` |
| `data` | bytes | raw 출력 바이트 (ANSI 시퀀스 포함) |
| `size` | string | 데이터 크기 |

#### 한계

- Ghostty config 변경 필요 (전체 cmux 세션에 영향)
- 프록시 크래시 시 셸도 종료됨
- raw bytes에 ANSI 이스케이프 시퀀스가 포함 → 텍스트로 보려면 파싱 필요
- 패스워드 등 민감한 키 입력도 캡처됨 → 보안 고려 필요


### 15.6 방법 비교 및 권장

| 기준 | 방법 1: read-screen 폴링 | 방법 2: script 래핑 | 방법 3: PTY 프록시 |
|------|----------------------|------------------|-----------------|
| 구현 난이도 | 낮음 | 중간 | 높음 |
| cmux 수정 필요 | 없음 | 없음 (--command 활용) | Ghostty config 변경 |
| 입력 캡처 | 불가 | 에코만 | 가능 (raw bytes) |
| 출력 캡처 | 폴링 (1초 간격) | 전체 기록 | 실시간 스트림 |
| 누락 가능성 | 있음 (폴링 간격) | 없음 | 없음 |
| 기존 세션 적용 | 가능 | 불가 | 불가 |
| ANSI 파싱 필요 | 불필요 (텍스트 반환) | 필요 | 필요 |
| 성능 영향 | 소켓 호출 오버헤드 | 최소 (파일 기록) | 최소 (PTY 중계) |
| 보안 위험 | 낮음 | 중간 | 높음 (키 입력 전체) |

#### 권장 조합

```
1단계 (즉시 시작):
  소켓 프록시 (SPEC.md 기존 내용) + read-screen 폴링 (방법 1)
  → 소켓 API 트래픽 + 화면 변화 모두 Redis에 적재
  → 기존 세션에도 적용 가능

2단계 (필요 시 확장):
  방법 3 (PTY 프록시) 추가
  → 실시간 입출력 스트림이 필요한 경우
  → Ghostty config의 command를 프록시로 교체

3단계 (cmux 업데이트 대기):
  cmux에 pipe-pane 기능이 구현되면 (issue #153)
  → 네이티브 소켓 API로 실시간 출력 스트리밍 가능
  → 방법 1~3이 모두 불필요해짐
```


### 15.7 통합 모니터링 아키텍처

소켓 프록시 + read-screen 폴링을 결합한 전체 구조:

```
                          ┌──────────────────────────────────────┐
                          │          Redis Streams               │
                          │                                      │
                          │  cmux:requests    (소켓 요청)         │
                          │  cmux:responses   (소켓 응답)         │
                          │  cmux:terminal_output (화면 변화)     │
                          │  cmux:terminal_input  (PTY 입력 *)   │
                          └──────────────┬───────────────────────┘
                                         │
            ┌────────────────────────────┼────────────────────┐
            │                            │                    │
    ┌───────┴───────┐           ┌────────┴────────┐   ┌──────┴──────┐
    │ Socket Proxy  │           │ Screen Poller   │   │ PTY Proxy   │
    │ (proxy.py)    │           │ (polling_       │   │ (pty_proxy  │
    │               │           │  monitor.py)    │   │  .py) *     │
    │ 소켓 제어 명령  │           │ read-screen 폴링│   │ 실시간 I/O * │
    └───────┬───────┘           └────────┬────────┘   └──────┬──────┘
            │                            │                    │
    ┌───────┴───────┐           ┌────────┴────────┐   ┌──────┴──────┐
    │/tmp/cmux.sock │           │ cmux Socket API │   │ Ghostty PTY │
    │(프록시 리스닝)  │           │ (read_text RPC) │   │ (셸 경로)   │
    └───────────────┘           └─────────────────┘   └─────────────┘

    * 방법 3은 선택적 (2단계에서 필요 시 추가)
```
