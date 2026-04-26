# cmux Socket Proxy — Redis Stream 트래픽 캡처 시스템

## 기술 명세 문서 (Claude Code 개발용)

> 작성일: 2026-03-29
> 목적: cmux 맥 앱의 Unix Socket 트래픽을 투명하게 프록시하면서 모든 요청/응답을 Redis Stream에 적재하는 시스템

---

## 1. 프로젝트 개요

### 1.1 배경

cmux는 Ghostty 기반의 네이티브 macOS 터미널 앱으로, AI 코딩 에이전트를 병렬 관리한다. Swift + AppKit으로 구축되었으며, Unix Domain Socket(`/tmp/cmux.sock`)을 통해 CLI 및 외부 스크립트와 통신한다.

이 프로젝트는 cmux의 소켓 트래픽(요청/응답)을 Redis Stream에 적재하여 실시간 모니터링, 레이턴시 분석, 트래픽 패턴 분석 등을 가능하게 한다.

### 1.2 설계 원칙

- **무침습(Non-invasive)**: cmux 앱 소스코드 수정 없음. 바이너리 배포 앱을 그대로 사용.
- **투명 프록시**: 기존 CLI 및 스크립트가 변경 없이 동작.
- **비동기 배치 적재**: 프록시 레이턴시 최소화 (~0.1ms).
- **Consumer Group**: 여러 처리기가 동일 스트림을 독립적으로 소비.
- **안전한 원복**: 프록시 종료 시 즉시 원래 상태로 복원 가능.

### 1.3 기술 스택

| 구성요소 | 기술 | 비고 |
|---------|------|------|
| 프록시 서버 | Python 3.10+ / asyncio | 비동기 소켓 중계 |
| 메시지 큐 | Redis Stream (XADD/XREAD) | redis-py async |
| 운영 스크립트 | Bash | macOS LaunchAgent 지원 |
| 모니터링 | Python CLI | 실시간 트래픽 표시 |
| Consumer | Python / Consumer Group | 분석/웹훅/DB 저장 |

### 1.4 의존성

```
redis>=5.0.0       # Python redis 클라이언트 (async 지원)
Redis Server 7.0+  # Redis Stream 지원
Python 3.10+       # asyncio, match-case 등
```

---

## 2. 아키텍처

### 2.1 전체 구조

```
┌──────────────┐     /tmp/cmux.sock      ┌────────────────┐     /tmp/cmux-real.sock     ┌──────────┐
│  cmux CLI /  │ ◄─────────────────────► │  Socket Proxy  │ ◄────────────────────────► │  cmux    │
│  외부 스크립트 │    (기존 경로 그대로)      │  (proxy.py)    │    (이동된 경로)             │  App     │
└──────────────┘                         │                │                             └──────────┘
                                         │   ┌──────────┐ │
                                         │   │  Redis   │ │
                                         │   │ Streams  │ │
                                         │   └──────────┘ │
                                         └────────────────┘
                                                 │
                                    ┌────────────┼────────────┐
                                    ▼            ▼            ▼
                              ┌──────────┐ ┌──────────┐ ┌──────────┐
                              │ monitor  │ │ consumer │ │ consumer │
                              │ (실시간)  │ │ (분석)    │ │ (webhook)│
                              └──────────┘ └──────────┘ └──────────┘
```

### 2.2 cmux 소켓 프로토콜

cmux는 두 가지 프로토콜을 지원한다:

#### v2 JSON-RPC (현재 주력)
```
→ 요청: {"id":"req-1","method":"workspace.list","params":{}}\n
← 응답: {"id":"req-1","ok":true,"result":{"workspaces":[...]}}\n
```

- 줄바꿈(`\n`)으로 메시지 구분
- `method` 필드: 네임스페이스.동작 형식 (예: `workspace.list`, `surface.split`, `notification.create`)
- `id` 필드: 요청-응답 매칭용 (클라이언트가 지정)
- `ok` 필드: 응답 성공/실패 여부

#### v1 레거시 텍스트 (하위 호환)
```
→ 요청: ping\n
← 응답: PONG\n

→ 요청: send echo hello\n
← 응답: OK\n
```

- 공백으로 구분된 텍스트 명령
- JSON 파싱 실패 시 v1으로 처리

### 2.3 cmux 앱의 계층 구조

소켓 API에서 사용하는 리소스 계층:

```
Window (macOS 윈도우)
  └── Workspace (사이드바 엔트리, 환경변수: CMUX_WORKSPACE_ID)
        └── Pane (분할 영역)
              └── Surface (Pane 내 탭, 환경변수: CMUX_SURFACE_ID)
                    └── Panel (Terminal 또는 Browser)
```

ID 참조 형식: `window:1`, `workspace:2`, `surface:3`, `pane:4`

### 2.4 주요 소켓 메서드 목록

| 카테고리 | 메서드 | 설명 |
|---------|--------|------|
| 시스템 | `system.ping` | 연결 확인 |
| 시스템 | `system.capabilities` | 사용 가능한 메서드 목록 |
| 시스템 | `system.identify` | 현재 포커스 컨텍스트 |
| 워크스페이스 | `workspace.list` | 워크스페이스 목록 |
| 워크스페이스 | `workspace.create` | 새 워크스페이스 생성 |
| 워크스페이스 | `workspace.select` | 워크스페이스 전환 |
| 워크스페이스 | `workspace.current` | 현재 워크스페이스 |
| 워크스페이스 | `workspace.close` | 워크스페이스 닫기 |
| 서피스 | `surface.list` | 서피스 목록 |
| 서피스 | `surface.split` | 분할 생성 |
| 서피스 | `surface.focus` | 서피스 포커스 |
| 서피스 | `surface.send_text` | 텍스트 입력 전송 |
| 서피스 | `surface.send_key` | 키 입력 전송 |
| 알림 | `notification.create` | 알림 생성 |
| 알림 | `notification.list` | 알림 목록 |
| 알림 | `notification.clear` | 알림 초기화 |
| 브라우저 | `browser.*` | 브라우저 자동화 (navigate, click, eval 등) |
| 사이드바 | `set_status`, `set_progress`, `log` | 사이드바 메타데이터 |

---

## 3. 소켓 교체 원리

### 3.1 Unix Domain Socket의 mv 동작

cmux 앱이 실행 중일 때 소켓 파일을 `mv`해도 앱이 정상 동작하는 이유:

```
1. cmux 앱이 bind("/tmp/cmux.sock") 호출
   → 커널이 inode 생성
   → 서버의 file descriptor(fd)에 해당 inode 바인딩
   → "/tmp/cmux.sock"은 inode를 가리키는 파일 시스템 경로(이름)

2. mv /tmp/cmux.sock /tmp/cmux-real.sock 실행
   → 파일 시스템에서 경로명만 변경 (inode 자체는 동일)
   → 서버의 fd는 여전히 같은 inode에 바인딩되어 있음
   → 서버는 "/tmp/cmux-real.sock" 경로로 계속 accept() 가능

3. 프록시가 bind("/tmp/cmux.sock") 호출
   → 새로운 inode 생성
   → 클라이언트의 새 연결은 프록시로 라우팅
   → 프록시가 "/tmp/cmux-real.sock"(원본 cmux)으로 중계
```

핵심: fd 기반 바인딩이므로 파일 경로 변경이 기존 서버에 영향을 주지 않는다.

### 3.2 세 가지 적용 방법

#### 방법 A: 런타임 소켓 교체 (inject)

cmux 앱이 이미 실행 중인 상태에서 즉시 적용. 앱 재시작 불필요.

```
실행 순서:
1. cmux 앱 실행 중 → /tmp/cmux.sock 존재
2. mv /tmp/cmux.sock /tmp/cmux-real.sock
3. 이동된 소켓으로 ping 테스트 (cmux 앱 정상 응답 확인)
4. 프록시가 /tmp/cmux.sock에서 리스닝 시작
5. 프록시가 /tmp/cmux-real.sock으로 중계
6. 프록시 경로로 ping 테스트 (전체 파이프라인 확인)
7. 실패 시: mv /tmp/cmux-real.sock /tmp/cmux.sock (자동 원복)
```

주의: cmux 앱이 재시작되면 `/tmp/cmux.sock`에 새로 `bind()`를 시도하므로 프록시와 충돌 발생. 이 경우 프록시를 먼저 종료하거나 방법 B/C를 사용.

#### 방법 B: 환경변수로 앱 재시작 (restart-app)

cmux 앱을 종료하고 다른 소켓 경로로 재시작. 깔끔한 분리.

```
실행 순서:
1. cmux 앱 종료 (osascript → pkill 순서)
2. 기존 소켓 파일 정리
3. 프록시를 /tmp/cmux.sock에서 먼저 리스닝 시작
4. cmux 앱을 CMUX_SOCKET_PATH=/tmp/cmux-real.sock 환경변수와 함께 실행
5. cmux 앱이 /tmp/cmux-real.sock 생성 대기 (최대 15초)
6. 프록시를 통한 연결 확인
```

#### 방법 C: LaunchAgent 자동화 (install)

부팅/로그인 시 자동으로 프록시 → cmux 순서를 보장.

```
구성:
- LaunchAgent plist: ~/Library/LaunchAgents/com.cmux.socket-proxy.plist
  → 프록시를 /tmp/cmux.sock에서 리스닝
  → RunAtLoad=true, KeepAlive (비정상 종료 시 재시작)

- cmux 앱 실행 방법 (택 1):
  a) 래퍼 스크립트를 로그인 항목에 등록
  b) defaults write 로 LSEnvironment에 CMUX_SOCKET_PATH 주입
  c) 수동으로 CMUX_SOCKET_PATH=/tmp/cmux-real.sock open -a cmux 실행
```

---

## 4. 파일 구조 및 각 파일 명세

```
cmux-socket-proxy/
├── proxy.py              # 메인 프록시 서버
├── monitor.py            # 실시간 트래픽 모니터
├── consumer.py           # Consumer Group 기반 처리기
├── cmux-proxy.sh         # 통합 운영 스크립트
├── requirements.txt      # Python 의존성
└── README.md             # 사용 문서
```

---

## 5. proxy.py — 메인 프록시 서버 명세

### 5.1 클래스 구조

```
CmuxSocketProxy          # 메인 서버
├── RedisStreamWriter     # Redis 배치 적재
└── ConnectionHandler     # 개별 연결 처리
```

### 5.2 ProxyConfig (설정)

```python
@dataclass
class ProxyConfig:
    listen_path: str = "/tmp/cmux.sock"          # 프록시 리스닝 경로
    upstream_path: str = "/tmp/cmux-real.sock"    # cmux 앱 실제 소켓 경로
    redis_url: str = "redis://localhost:6379/0"
    stream_requests: str = "cmux:requests"        # 요청 스트림 키
    stream_responses: str = "cmux:responses"      # 응답 스트림 키
    stream_maxlen: int = 10000                    # 스트림 최대 길이
    batch_size: int = 50                          # 배치 적재 크기
    flush_interval: float = 0.1                   # 배치 플러시 간격 (초)
    buffer_size: int = 65536                      # 소켓 읽기 버퍼
    connect_timeout: float = 5.0                  # upstream 연결 타임아웃
    idle_timeout: float = 300.0                   # 유휴 연결 타임아웃
    log_level: str = "INFO"
    log_file: str | None = None
```

환경변수 오버라이드:
- `CMUX_PROXY_LISTEN` → listen_path
- `CMUX_PROXY_UPSTREAM` → upstream_path
- `CMUX_PROXY_REDIS_URL` → redis_url
- `CMUX_PROXY_STREAM_REQ` → stream_requests
- `CMUX_PROXY_STREAM_RES` → stream_responses
- `CMUX_PROXY_MAXLEN` → stream_maxlen
- `CMUX_PROXY_LOG_LEVEL` → log_level

CLI 인자가 환경변수보다 우선:
```
python3 proxy.py --listen /tmp/cmux.sock --upstream /tmp/cmux-real.sock --redis-url redis://host:6379/0
```

### 5.3 RedisStreamWriter (배치 적재)

```
동작 방식:
1. enqueue(stream_key, entry) → asyncio.Queue에 엔트리 추가
2. flush_loop() → flush_interval(0.1초)마다 또는 batch_size(50) 도달 시 실행
3. flush_batch() → Queue에서 batch_size만큼 꺼내 Redis pipeline으로 일괄 XADD
4. XADD 시 MAXLEN~(approximate) 사용하여 스트림 크기 자동 제한

에러 처리:
- Redis 연결 실패 시: 프록시는 계속 동작, 큐에 보관 후 재연결 시 플러시
- XADD 실패 시: 실패한 항목을 큐에 다시 삽입 (1회)
- Redis 완전 불능 시: 큐 오버플로우까지 프록시 동작 유지 (데이터 유실 가능)
```

### 5.4 ConnectionHandler (연결 처리)

```
동작 방식:
1. 클라이언트 연결 수신 → conn_id 생성 (timestamp-uuid12)
2. upstream(cmux 앱) Unix Socket 연결
3. 양방향 파이프 구성:
   a) Client → Proxy → Upstream (요청 방향)
   b) Upstream → Proxy → Client (응답 방향)
4. 각 방향에서 readline()으로 줄바꿈 기준 메시지 단위 캡처
5. 메시지마다 Redis Stream 엔트리 생성 후 enqueue
6. 원본 바이트를 그대로 상대방에게 전달

프로토콜 처리:
- cmux 소켓 프로토콜은 줄바꿈(\n) 구분이므로 readline() 사용
- JSON 파싱 시도하여 메타데이터(method, req_id, ok) 추출
- JSON 파싱 실패 시(v1 레거시) 첫 토큰을 method로 사용
- 파싱 실패해도 원본 데이터는 항상 기록
```

### 5.5 Redis Stream 엔트리 구조

#### 요청 엔트리 (cmux:requests)

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `conn_id` | string | 연결 고유 ID | `1711234567890-a1b2c3d4e5f6` |
| `ts` | string | 타임스탬프 (Unix ms) | `1711234567890` |
| `direction` | string | 항상 `"request"` | `request` |
| `method` | string | JSON-RPC method 또는 v1 명령 | `workspace.list` |
| `req_id` | string | JSON-RPC id (응답 매칭용) | `ws-list` |
| `data` | string | 원본 JSON/텍스트 데이터 | `{"id":"ws-list","method":"workspace.list","params":{}}` |
| `size` | string | 데이터 크기 (bytes) | `52` |

#### 응답 엔트리 (cmux:responses)

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `conn_id` | string | 연결 고유 ID (요청과 동일) | `1711234567890-a1b2c3d4e5f6` |
| `ts` | string | 타임스탬프 (Unix ms) | `1711234567893` |
| `direction` | string | 항상 `"response"` | `response` |
| `method` | string | 응답에 method가 있으면 추출 | - |
| `req_id` | string | JSON-RPC id (요청 매칭용) | `ws-list` |
| `ok` | string | 응답 성공 여부 | `true` |
| `result_keys` | string | result 객체의 주요 키 (쉼표 구분, 최대 200자) | `workspaces` |
| `data` | string | 원본 JSON/텍스트 데이터 | `{"id":"ws-list","ok":true,"result":{...}}` |
| `size` | string | 데이터 크기 (bytes) | `384` |

**참고**: Redis Stream은 모든 값을 문자열로 저장하므로 숫자도 string 타입.

### 5.6 CmuxSocketProxy (메인 서버)

```
동작 방식:
1. Redis 연결 (RedisStreamWriter.start)
2. listen_path에 Unix Socket 서버 생성 (asyncio.start_unix_server)
3. 소켓 퍼미션 0700 설정
4. 새 연결마다 ConnectionHandler 생성하여 비동기 처리
5. SIGINT/SIGTERM 시 graceful shutdown:
   a) 서버 소켓 닫기
   b) 잔여 큐 Redis 플러시
   c) Redis 연결 닫기
   d) 소켓 파일 삭제
```

---

## 6. monitor.py — 실시간 모니터 명세

### 6.1 기능

```
1. 최근 기록 표시 (--history N)
   - cmux:requests와 cmux:responses를 합쳐서 시간순 정렬

2. 실시간 모니터링
   - XREAD BLOCK 1000ms로 새 데이터 대기
   - 컬러 포맷팅: 요청(→ REQ 시안), 응답(← RES 초록)
   - 성공(✓)/실패(✗) 표시
   - 데이터 미리보기 (120자 초과 시 축약)

3. 필터링 (--method)
   - method 이름 부분 매칭 (대소문자 무시)

4. 통계 (--stats)
   - 스트림 길이, 첫/마지막 엔트리 ID
   - 최근 1분간 method별 호출 횟수
```

### 6.2 CLI 인터페이스

```
python3 monitor.py                      # 실시간 모니터
python3 monitor.py --history 50         # 최근 50건 + 실시간
python3 monitor.py --method workspace   # workspace 관련만 필터
python3 monitor.py --json               # JSON 출력
python3 monitor.py --stats              # 통계만 표시
python3 monitor.py --redis-url redis://host:6379/0
```

### 6.3 출력 포맷

```
# 텍스트 출력 (기본)
14:23:45.123 → REQ [a1b2c3d4] workspace.list  (52B) {"id":"ws-list","method":"workspace.list",...}
14:23:45.126 ← RES [a1b2c3d4] workspace.list ✓ (384B) {"id":"ws-list","ok":true,...}

# JSON 출력 (--json)
{"stream_id":"1711234567890-0","conn_id":"...","ts":"...","direction":"request","method":"workspace.list","data":"..."}
```

---

## 7. consumer.py — Consumer Group 처리기 명세

### 7.1 아키텍처

```
Consumer Group 기반:
- 동일 Group 내 여러 Consumer 실행 → 부하 분산
- 서로 다른 Group → 동일 데이터를 각각 독립 처리
- XREADGROUP BLOCK으로 새 메시지 대기
- 처리 완료 후 XACK

Group 자동 생성:
- Consumer 시작 시 XGROUP CREATE (mkstream=True)
- 이미 존재하면(BUSYGROUP) 무시
```

### 7.2 핸들러 인터페이스

```python
class BaseHandler:
    async def handle(self, stream_key: str, entry_id: str, fields: dict):
        """개별 엔트리 처리"""
        raise NotImplementedError

    async def flush(self):
        """주기적 플러시 (10초마다 호출)"""
        pass
```

### 7.3 내장 핸들러

#### LogHandler
단순 로그 출력. 디버깅용.

#### LatencyHandler
요청-응답 쌍을 `conn_id:req_id` 키로 매칭하여 레이턴시 측정.
- pending 딕셔너리에 요청 타임스탬프 저장
- 응답 수신 시 차이 계산
- flush() 시 avg, p50, p99 통계 출력

#### AggregationHandler
1분 윈도우 기반 집계.
- method별 호출 횟수 카운트
- ok=false 응답의 에러율 계산
- flush() 시 통계 출력 후 윈도우 리셋

#### WebhookHandler (확장 예시)
특정 method 호출 시 외부 Webhook 전송.
- trigger_methods 목록으로 필터
- 요청 방향만 처리
- 실제 HTTP 호출은 aiohttp로 구현 필요

### 7.4 CLI 인터페이스

```
python3 consumer.py                            # 기본(log) 핸들러
python3 consumer.py --handler latency          # 레이턴시 분석
python3 consumer.py --handler aggregation      # 시간 윈도우 집계
python3 consumer.py --group analytics          # Consumer Group 지정
python3 consumer.py --consumer worker-2        # Consumer 이름 지정
python3 consumer.py --streams cmux:requests    # 특정 스트림만 구독
```

---

## 8. cmux-proxy.sh — 통합 운영 스크립트 명세

### 8.1 명령어

| 명령 | 설명 | cmux 앱 재시작 |
|------|------|--------------|
| `inject` | 방법 A: 실행 중 소켓 즉시 교체 | 불필요 |
| `restart-app` | 방법 B: 환경변수와 함께 앱 재시작 | 필요 |
| `install` | 방법 C: LaunchAgent 자동화 설치 | 필요 |
| `uninstall` | LaunchAgent 제거 및 모든 설정 원복 | 필요 |
| `stop` | 프록시 종료 및 소켓 원복 | 불필요 |
| `status` | 전체 상태 확인 | - |
| `monitor` | 실시간 트래픽 모니터 실행 | - |

### 8.2 inject 명령 상세 흐름

```bash
# 사전 검증
1. Redis 서버 실행 확인 (redis-cli ping)
2. Python redis 패키지 확인
3. 프록시가 이미 실행 중인지 확인 (PID 파일)
4. cmux 앱이 실행 중인지 확인 (pgrep -x "cmux")
5. /tmp/cmux.sock 소켓 파일 존재 확인

# 소켓 교체
6. mv /tmp/cmux.sock /tmp/cmux-real.sock
7. /tmp/cmux-real.sock으로 ping 테스트 (Python socket 연결)
   → 실패 시: mv /tmp/cmux-real.sock /tmp/cmux.sock (원복) + 에러

# 프록시 시작
8. nohup python3 proxy.py --listen /tmp/cmux.sock --upstream /tmp/cmux-real.sock &
9. PID를 /tmp/cmux-proxy.pid에 저장
10. 0.8초 대기 후 프로세스 생존 확인
    → 실패 시: 소켓 원복 + 에러

# 검증
11. /tmp/cmux.sock (프록시)으로 ping 테스트
12. 성공 정보 출력
```

### 8.3 restart-app 명령 상세 흐름

```bash
# 앱 종료
1. osascript -e 'tell application "cmux" to quit'
2. 2초 대기
3. 앱이 아직 실행 중이면 pkill -x "cmux"
4. 소켓 파일 정리 (rm -f /tmp/cmux.sock /tmp/cmux-real.sock)

# 프록시 먼저 시작
5. python3 proxy.py --listen /tmp/cmux.sock --upstream /tmp/cmux-real.sock &

# cmux 앱 재시작
6. CMUX_SOCKET_PATH=/tmp/cmux-real.sock open -a cmux
7. /tmp/cmux-real.sock 생성 대기 (최대 15초, 0.5초 폴링)
8. 연결 확인
```

### 8.4 install 명령 상세 흐름

```bash
# LaunchAgent plist 생성
1. ~/Library/LaunchAgents/com.cmux.socket-proxy.plist 작성
   - ProgramArguments: python3 proxy.py --listen ... --upstream ...
   - RunAtLoad: true
   - KeepAlive: SuccessfulExit=false (비정상 종료 시 재시작)

# cmux 래퍼 스크립트 생성
2. cmux-launch-wrapper.sh 작성
   - CMUX_SOCKET_PATH=/tmp/cmux-real.sock open -a cmux

# 로드
3. launchctl load ~/Library/LaunchAgents/com.cmux.socket-proxy.plist

# cmux 앱 소켓 경로 변경 방법 안내:
   a) 래퍼 스크립트를 로그인 항목에 등록
   b) defaults write ai.manaflow.cmuxterm LSEnvironment -dict-add CMUX_SOCKET_PATH '/tmp/cmux-real.sock'
   c) 즉시 restart-app 실행
```

### 8.5 stop 명령 상세 흐름

```bash
1. PID 파일에서 프록시 PID 읽기
2. kill → 1초 대기 → kill -9 (필요 시)
3. PID 파일 삭제
4. /tmp/cmux-real.sock 존재 + /tmp/cmux.sock 부재 시:
   mv /tmp/cmux-real.sock /tmp/cmux.sock (원복)
5. 프록시 소켓 파일 정리
```

### 8.6 status 명령 출력

```
━━━ cmux Socket Proxy 상태 ━━━

  cmux 앱      : 실행 중 (PID: 1234)
  프록시        : 실행 중 (PID: 5678)

  소켓 상태:
    /tmp/cmux.sock       : 존재
      └─ 소유 프로세스: python3 (PID: 5678)
    /tmp/cmux-real.sock  : 존재 (cmux 원본)

  Redis:
    서버         : 실행 중
    cmux:requests  : 847 entries
    cmux:responses : 832 entries
    최근 요청     : "method":"workspace.list"

  LaunchAgent  : 설치됨 + 로드됨

  로그 파일    : /tmp/cmux-proxy.log (12K)
  최근 로그    : 2026-03-29 14:23:45 [proxy] INFO 프록시 시작
```

---

## 9. 소켓 경로 및 파일 경로 정리

| 경로 | 용도 | 생성 주체 |
|------|------|----------|
| `/tmp/cmux.sock` | 클라이언트가 연결하는 경로 (프록시 적용 후: 프록시) | cmux 앱 → 프록시 |
| `/tmp/cmux-real.sock` | cmux 앱의 실제 소켓 (프록시 적용 후) | inject: mv로 이동 / restart-app: 환경변수로 지정 |
| `/tmp/cmux-proxy.pid` | 프록시 PID | cmux-proxy.sh |
| `/tmp/cmux-proxy.log` | 프록시 로그 | proxy.py |
| `~/Library/LaunchAgents/com.cmux.socket-proxy.plist` | LaunchAgent | cmux-proxy.sh install |

### cmux 앱 관련 환경변수

| 변수 | 설명 | 프록시 관련 |
|------|------|-----------|
| `CMUX_SOCKET_PATH` | cmux 앱의 소켓 생성 경로 오버라이드 | 방법 B/C에서 `/tmp/cmux-real.sock`으로 설정 |
| `CMUX_SOCKET_ENABLE` | 소켓 활성화 (1/0) | - |
| `CMUX_SOCKET_MODE` | 접근 모드 (cmuxOnly, allowAll, off) | - |
| `CMUX_WORKSPACE_ID` | 현재 워크스페이스 ID (자동 설정) | - |
| `CMUX_SURFACE_ID` | 현재 서피스 ID (자동 설정) | - |

---

## 10. Redis Stream 운영

### 10.1 주요 Redis 명령

```bash
# 스트림 길이
redis-cli XLEN cmux:requests
redis-cli XLEN cmux:responses

# 최근 N건 (최신순)
redis-cli XREVRANGE cmux:requests + - COUNT 10

# 특정 시간 이후 (Unix ms)
redis-cli XRANGE cmux:requests 1711234567890-0 +

# 스트림 정보
redis-cli XINFO STREAM cmux:requests

# Consumer Group 정보
redis-cli XINFO GROUPS cmux:requests

# Consumer Group의 미처리 메시지 (pending)
redis-cli XPENDING cmux:requests analytics-group

# 스트림 초기화
redis-cli DEL cmux:requests cmux:responses

# 수동 trim
redis-cli XTRIM cmux:requests MAXLEN ~ 5000
```

### 10.2 MAXLEN 전략

```
기본값: 10000 (MAXLEN ~)
- ~ (approximate): 정확한 10000이 아닌 근사값으로 trim (성능 최적화)
- 실제로는 radix tree 노드 단위로 trim하므로 ±100 정도 오차
- 10000건 × 평균 500B/건 = ~5MB 메모리 사용
- 필요 시 --maxlen 옵션으로 조정
```

### 10.3 Consumer Group 운영

```
수평 확장:
  동일 Group 내 여러 Consumer → 메시지가 분산됨
  → python3 consumer.py --group analytics --consumer worker-1
  → python3 consumer.py --group analytics --consumer worker-2

독립 처리:
  서로 다른 Group → 동일 데이터를 각각 처리
  → python3 consumer.py --group latency --handler latency
  → python3 consumer.py --group stats --handler aggregation
```

---

## 11. 에러 처리 및 장애 대응

### 11.1 Redis 장애

```
증상: Redis 서버 다운 또는 네트워크 단절
동작: 프록시는 계속 동작 (소켓 중계는 유지)
      큐에 엔트리가 쌓임
      Redis 복구 시 자동 재연결 + 큐 플러시
영향: 장애 기간의 데이터 유실 가능 (큐 오버플로우 시)
```

### 11.2 프록시 크래시

```
증상: proxy.py 프로세스 종료
동작: /tmp/cmux.sock 파일 삭제됨
      cmux CLI 연결 실패
대응: LaunchAgent 설치 시 자동 재시작 (KeepAlive)
      수동: ./cmux-proxy.sh inject 재실행
```

### 11.3 cmux 앱 재시작

```
증상: cmux 앱이 업데이트 등으로 재시작됨
동작(inject 모드):
  앱이 /tmp/cmux.sock에 bind 시도 → Address already in use
  → 앱이 다른 경로에 소켓 생성하거나 실패
대응:
  ./cmux-proxy.sh stop  (프록시 종료 + 소켓 원복)
  → cmux 앱 정상 재시작
  → ./cmux-proxy.sh inject (다시 프록시 삽입)

  또는 방법 C(LaunchAgent)로 전환하면 순서 보장
```

### 11.4 소켓 퍼미션

```
프록시 소켓: 0700 (소유자만 접근)
cmux 앱의 기본 동작과 동일하게 설정
공유 머신에서는 CMUX_SOCKET_MODE=cmuxOnly 유지 권장
```

---

## 12. 테스트 시나리오

### 12.1 기본 동작 테스트

```bash
# 1. 프록시 시작
./cmux-proxy.sh inject

# 2. cmux CLI 동작 확인
cmux ping
cmux list-workspaces
cmux list-workspaces --json

# 3. Redis 데이터 확인
redis-cli XLEN cmux:requests
redis-cli XLEN cmux:responses
redis-cli XREVRANGE cmux:requests + - COUNT 3
redis-cli XREVRANGE cmux:responses + - COUNT 3
```

### 12.2 요청-응답 매칭 테스트

```bash
# Consumer에서 레이턴시 측정
python3 consumer.py --handler latency &

# 여러 명령 실행
cmux list-workspaces
cmux ping
cmux capabilities

# Consumer 출력에서 레이턴시 확인
#   ⏱ workspace.list    latency=3ms
#   ⏱ system.ping       latency=1ms
#   ⏱ system.capabilities latency=2ms
```

### 12.3 프록시 종료/원복 테스트

```bash
# 프록시 종료
./cmux-proxy.sh stop

# cmux CLI가 직접 연결로 정상 동작하는지 확인
cmux ping
cmux list-workspaces
```

### 12.4 Redis 장애 시뮬레이션

```bash
# 프록시 실행 중
./cmux-proxy.sh inject

# Redis 중지
brew services stop redis

# cmux CLI가 여전히 동작하는지 확인 (프록시 중계는 유지)
cmux ping

# Redis 재시작
brew services start redis

# 새 명령 실행 후 Redis에 데이터가 기록되는지 확인
cmux list-workspaces
redis-cli XLEN cmux:requests
```

---

## 13. 확장 포인트

### 13.1 커스텀 Consumer 작성

```python
from consumer import BaseHandler, run_consumer

class MyHandler(BaseHandler):
    async def handle(self, stream_key, entry_id, fields):
        method = fields.get("method", "")
        if method == "notification.create":
            # 알림 생성 시 Slack 웹훅 전송
            data = json.loads(fields.get("data", "{}"))
            params = data.get("params", {})
            title = params.get("title", "")
            body = params.get("body", "")
            await send_slack_webhook(title, body)

    async def flush(self):
        pass

asyncio.run(run_consumer(
    redis_url="redis://localhost:6379/0",
    group="slack-notifier",
    consumer_name="worker-1",
    handler=MyHandler(),
))
```

### 13.2 데이터 파이프라인 예시

```
Redis Stream → Consumer (MySQL 저장)
  → 시간별/일별 집계 테이블
  → method별 호출 패턴 분석
  → 레이턴시 p50/p95/p99 추세

Redis Stream → Consumer (파일 로깅)
  → JSON Lines 파일 (.jsonl)
  → 로그 로테이션 (logrotate)

Redis Stream → Consumer (실시간 대시보드)
  → WebSocket → 브라우저 대시보드
  → 트래픽 히트맵, 에러율 차트
```

### 13.3 필터링 프록시 확장

```
특정 method만 Redis에 기록:
  → ProxyConfig에 include_methods / exclude_methods 추가
  → ConnectionHandler._build_entry()에서 필터링

민감 데이터 마스킹:
  → data 필드에서 특정 패턴 치환
  → 예: surface.send_text의 text 파라미터 마스킹

요청 변조 (주의: 디버깅 목적만):
  → upstream으로 전달 전 요청 수정
  → 예: 특정 workspace_id를 다른 값으로 치환
```

---

## 14. 운영 체크리스트

### 최초 설치

```
[ ] Redis 서버 설치 및 실행 (brew install redis && brew services start redis)
[ ] Python 의존성 설치 (pip3 install redis)
[ ] 프로젝트 파일 배치
[ ] chmod +x cmux-proxy.sh
[ ] cmux 앱이 실행 중인 상태에서 ./cmux-proxy.sh inject 실행
[ ] cmux ping 으로 정상 동작 확인
[ ] redis-cli XLEN cmux:requests 로 데이터 적재 확인
```

### 상시 운영 전환

```
[ ] ./cmux-proxy.sh install 실행
[ ] cmux 앱의 소켓 경로 변경 (defaults write 또는 래퍼 스크립트)
[ ] 재부팅 후 자동 시작 확인
[ ] ./cmux-proxy.sh status 로 전체 상태 확인
```

### 제거

```
[ ] ./cmux-proxy.sh uninstall
[ ] defaults delete ai.manaflow.cmuxterm LSEnvironment (설정한 경우)
[ ] cmux 앱 재시작
[ ] redis-cli DEL cmux:requests cmux:responses (데이터 정리)
```
