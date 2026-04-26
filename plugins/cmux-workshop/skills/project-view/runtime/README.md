# cmux Monitor

cmux 앱의 Unix Domain Socket 트래픽을 투명하게 프록시하면서 Redis Stream에 적재하고, 웹 대시보드에서 실시간 모니터링하는 시스템.

## 요구사항

- macOS (cmux 앱 실행 환경)
- Python 3.10+
- Redis 7.0+
- Node.js 18+
- cmux 앱 실행 중

## 설치

```bash
# 1. Python 의존성
pip3 install -r requirements.txt

# 2. Redis 서버 (미설치 시)
brew install redis
brew services start redis

# 3. 웹 대시보드 의존성
cd web/server && npm install
cd ../client && npm install
```

## 프로젝트 구조

```
cmux-monitor/
├── proxy.py              # 소켓 프록시 서버 (asyncio)
├── polling_monitor.py    # 터미널 화면 폴링 모니터
├── monitor.py            # CLI 실시간 트래픽 모니터
├── consumer.py           # Consumer Group 처리기
├── cmux-proxy.sh         # 통합 운영 스크립트
├── requirements.txt      # Python 의존성
├── web/
│   ├── server/           # Express + socket.io + Redis
│   │   └── index.js
│   ├── client/           # Vite + React 대시보드
│   │   └── src/
│   └── scripts/dev.js    # 서버+클라이언트 동시 실행
├── SPEC.md               # 기술 명세 (소켓 프록시)
└── SPEC-Terminal-io.md   # 기술 명세 (터미널 I/O)
```

---

## 실행

### 1단계: 프록시 시작

cmux 소켓 트래픽을 캡처하려면 프록시를 먼저 실행해야 합니다.

#### 방법 A: inject (앱 재시작 불필요, 권장)

```bash
./cmux-proxy.sh inject
```

실행 중인 cmux 앱의 소켓을 즉시 교체합니다. cmux 앱 재시작이 필요 없습니다.

#### 방법 B: restart-app (깔끔한 분리)

```bash
./cmux-proxy.sh restart-app
```

cmux 앱을 종료하고 프록시를 먼저 시작한 뒤, 환경변수를 지정하여 cmux 앱을 재시작합니다.

#### 방법 C: install (부팅 시 자동 실행)

```bash
./cmux-proxy.sh install
```

macOS LaunchAgent를 등록하여 시스템 부팅 시 프록시가 자동으로 시작됩니다.

### 2단계: 터미널 화면 모니터링 (선택)

터미널 화면 변화를 캡처하려면 폴링 모니터를 실행합니다:

```bash
# 모든 surface 자동 감지 (기본)
python3 polling_monitor.py

# 특정 surface만
python3 polling_monitor.py --surface surface:1

# 빠른 폴링 (0.5초 간격)
python3 polling_monitor.py --interval 0.5

# 특정 워크스페이스만
python3 polling_monitor.py --workspace workspace:2
```

`cmux read-screen` API를 주기적으로 호출하여 화면 변경을 감지하고 `cmux:terminal_output` Redis Stream에 적재합니다.

### 3단계: 모니터링

#### 웹 대시보드 (권장)

```bash
cd web
npm run dev
```

- Express 서버: http://localhost:3001
- React 클라이언트: http://localhost:5173

브라우저에서 http://localhost:5173 을 엽니다.

웹 대시보드 기능:
- **Dashboard**: 전체 통계 카드, Top Methods, 실시간 트래픽 로그
- **All Traffic**: 전체 트래픽 로그 (필터링, 상세 보기)
- **Workspace 별 뷰**: 사이드바에서 워크스페이스를 선택하면 해당 트래픽만 필터링
- **Terminal 뷰**: 사이드바에서 surface를 선택하면 해당 터미널 화면 표시 (polling_monitor.py 실행 필요)

#### CLI 모니터

```bash
# 실시간 모니터
python3 monitor.py

# 최근 50건 + 실시간
python3 monitor.py --history 50

# 특정 메서드만 필터
python3 monitor.py --method workspace

# JSON 출력
python3 monitor.py --json

# 통계만 표시
python3 monitor.py --stats
```

#### Consumer Group 처리기

```bash
# 로그 출력
python3 consumer.py

# 레이턴시 측정
python3 consumer.py --handler latency

# 메서드별 집계
python3 consumer.py --handler aggregation

# Consumer Group/이름 지정
python3 consumer.py --group analytics --consumer worker-1
```

---

## 종료

### 프록시 종료

```bash
./cmux-proxy.sh stop
```

프록시를 종료하고 소켓을 원래 상태로 복원합니다. cmux 앱은 직접 연결로 계속 동작합니다.

### 웹 대시보드 종료

`cd web && npm run dev`로 시작한 경우 터미널에서 `Ctrl+C`로 종료합니다.

### LaunchAgent 제거

```bash
./cmux-proxy.sh uninstall
```

LaunchAgent를 제거하고 프록시를 종료합니다.

### 폴링 모니터 종료

`python3 polling_monitor.py`로 시작한 경우 `Ctrl+C`로 종료합니다.

### 전체 종료 순서

```bash
# 1. 웹 대시보드 종료 (Ctrl+C)
# 2. 폴링 모니터 종료 (Ctrl+C)
# 3. 프록시 종료 + 소켓 원복
./cmux-proxy.sh stop
# 4. cmux 정상 동작 확인
cmux ping
```

---

## 상태 확인

```bash
./cmux-proxy.sh status
```

출력 예시:

```
━━━ cmux Socket Proxy 상태 ━━━

  cmux 앱      : 실행 중 (PID: 8021)
  프록시        : 실행 중 (PID: 5678)

  소켓 상태:
    /Users/.../cmux/cmux.sock       : 존재
    /Users/.../cmux/cmux-real.sock  : 존재 (upstream)

  Redis:
    서버         : 실행 중
    cmux:requests  : 847 entries
    cmux:responses : 832 entries

  LaunchAgent  : 설치 안됨

  로그 파일    : /tmp/cmux-proxy.log (12K)
```

---

## 운영 스크립트 명령어

| 명령 | 설명 | cmux 재시작 |
|------|------|------------|
| `./cmux-proxy.sh inject` | 실행 중 소켓 즉시 교체 | 불필요 |
| `./cmux-proxy.sh restart-app` | 환경변수로 앱 재시작 | 필요 |
| `./cmux-proxy.sh install` | LaunchAgent 자동화 | 필요 |
| `./cmux-proxy.sh uninstall` | LaunchAgent 제거 | 필요 |
| `./cmux-proxy.sh stop` | 프록시 종료 + 소켓 원복 | 불필요 |
| `./cmux-proxy.sh status` | 전체 상태 확인 | - |
| `./cmux-proxy.sh monitor` | CLI 모니터 실행 | - |

---

## 소켓 경로

cmux 앱의 소켓 경로는 자동 감지됩니다:

```bash
cmux identify --json
# → { "socket_path": "/Users/.../Library/Application Support/cmux/cmux.sock", ... }
```

| 경로 | 용도 |
|------|------|
| `.../cmux/cmux.sock` | 클라이언트 연결 경로 (프록시 적용 후: 프록시) |
| `.../cmux/cmux-real.sock` | cmux 앱 실제 소켓 (프록시 적용 후) |
| `/tmp/cmux-proxy.pid` | 프록시 PID 파일 |
| `/tmp/cmux-proxy.log` | 프록시 로그 |

---

## Redis Stream

### 스트림 키

- `cmux:requests` — 소켓 API 요청 엔트리
- `cmux:responses` — 소켓 API 응답 엔트리
- `cmux:terminal_output` — 터미널 화면 변경 엔트리 (polling_monitor.py)

### 주요 Redis 명령

```bash
# 스트림 길이
redis-cli XLEN cmux:requests
redis-cli XLEN cmux:responses

# 최근 N건
redis-cli XREVRANGE cmux:requests + - COUNT 10

# 스트림 정보
redis-cli XINFO STREAM cmux:requests

# 스트림 초기화
redis-cli DEL cmux:requests cmux:responses
```

### 엔트리 구조

**요청** (`cmux:requests`):

| 필드 | 설명 | 예시 |
|------|------|------|
| `conn_id` | 연결 ID | `1711234567890-a1b2c3d4e5f6` |
| `ts` | 타임스탬프 (Unix ms) | `1711234567890` |
| `direction` | `"request"` | `request` |
| `method` | JSON-RPC method | `workspace.list` |
| `req_id` | 요청 ID | `ws-list` |
| `data` | 원본 데이터 | `{"id":"ws-list",...}` |
| `size` | 바이트 크기 | `52` |

**응답** (`cmux:responses`):

| 필드 | 설명 | 예시 |
|------|------|------|
| `conn_id` | 연결 ID | `1711234567890-a1b2c3d4e5f6` |
| `ts` | 타임스탬프 (Unix ms) | `1711234567893` |
| `direction` | `"response"` | `response` |
| `req_id` | 요청 ID (매칭용) | `ws-list` |
| `ok` | 성공 여부 | `true` |
| `result_keys` | result 주요 키 | `workspaces` |
| `data` | 원본 데이터 | `{"id":"ws-list","ok":true,...}` |
| `size` | 바이트 크기 | `384` |

---

## 장애 대응

### Redis 다운 시

프록시는 계속 동작합니다 (소켓 중계 유지). Redis 복구 시 자동 재연결됩니다.

```bash
# Redis 중지 → cmux 여전히 동작
brew services stop redis
cmux ping  # PONG

# Redis 재시작 → 새 데이터 적재 재개
brew services start redis
```

### 프록시 크래시 시

```bash
./cmux-proxy.sh stop    # 소켓 원복
./cmux-proxy.sh inject  # 다시 프록시 삽입
```

### cmux 앱 재시작 시 (inject 모드)

inject 모드에서 cmux 앱이 재시작되면 소켓 충돌이 발생합니다:

```bash
./cmux-proxy.sh stop    # 프록시 종료 + 소켓 원복
# cmux 앱 정상 재시작
./cmux-proxy.sh inject  # 다시 프록시 삽입
```

---

## 웹 대시보드 API

Express 서버(3001)가 제공하는 REST API:

| 엔드포인트 | 설명 |
|-----------|------|
| `GET /api/stats` | 전체 통계 (스트림 크기, 메서드별 카운트, 레이턴시, 에러율) |
| `GET /api/workspaces` | cmux 워크스페이스 목록 |
| `GET /api/traffic?limit=100` | 최근 N건 트래픽 |

WebSocket 이벤트 (socket.io):

| 이벤트 | 방향 | 설명 |
|--------|------|------|
| `init` | server→client | 초기 데이터 (stats + traffic) |
| `traffic` | server→client | 실시간 트래픽 엔트리 |
| `stats` | server→client | 5초 간격 통계 업데이트 |

---

## 환경변수

### 프록시 (proxy.py)

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `CMUX_PROXY_LISTEN` | 프록시 리스닝 경로 | 자동 감지 |
| `CMUX_PROXY_UPSTREAM` | upstream 소켓 경로 | 자동 감지 |
| `CMUX_PROXY_REDIS_URL` | Redis 연결 URL | `redis://localhost:6379/0` |
| `CMUX_PROXY_MAXLEN` | 스트림 최대 길이 | `10000` |
| `CMUX_PROXY_LOG_LEVEL` | 로그 레벨 | `INFO` |

### 웹 서버 (web/server)

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `PORT` | 서버 포트 | `3001` |
| `REDIS_URL` | Redis 연결 URL | `redis://localhost:6379/0` |
