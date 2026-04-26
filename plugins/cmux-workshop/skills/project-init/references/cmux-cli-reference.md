# cmux CLI Reference

cmux는 macOS 네이티브 터미널 멀티플렉서로, Unix 소켓 기반 CLI로 제어된다.
Swift로 구현되며 V2 JSON-RPC 프로토콜을 사용한다.

## Handle Inputs

모든 명령에서 window, workspace, pane, surface를 식별할 때 세 가지 형식 사용:
- **UUID**: `550e8400-e29b-41d4-a716-446655440000`
- **Short ref**: `window:1`, `workspace:2`, `pane:3`, `surface:4`
- **Index**: 숫자만 (생성 순서 기반)

출력 기본값은 refs. `--id-format uuids` 또는 `--id-format both`로 변경 가능.

## Environment Variables

| 변수 | 설명 |
|------|------|
| `CMUX_WORKSPACE_ID` | 현재 workspace (cmux 터미널 내 자동 설정) |
| `CMUX_SURFACE_ID` | 현재 surface (cmux 터미널 내 자동 설정) |
| `CMUX_TAB_ID` | 현재 tab (surface alias) |
| `CMUX_SOCKET_PATH` | Unix 소켓 경로 오버라이드 |

기본 소켓 경로: `~/Library/Application Support/cmux/cmux.sock`

---

## System & Connectivity

```bash
cmux ping                          # 소켓 연결 테스트
cmux version                       # 버전 표시
cmux capabilities                  # 사용 가능한 기능 목록 (V2: system.capabilities)
cmux identify [--workspace ID] [--surface ID] [--no-caller]
                                    # 호출자 컨텍스트 식별 (V2: system.identify)
cmux rpc <method> [json-params]    # V2 JSON-RPC 직접 호출
```

---

## Window Management

```bash
cmux list-windows                               # 모든 윈도우 목록
cmux current-window                              # 현재 활성 윈도우
cmux new-window                                  # 새 OS 윈도우 생성
cmux focus-window --window <id|ref>              # 윈도우 포커스
cmux close-window --window <id|ref>              # 윈도우 닫기
cmux move-workspace-to-window --workspace <id|ref> --window <id|ref>
                                                 # 워크스페이스를 다른 윈도우로 이동
```

---

## Workspace Management

```bash
cmux list-workspaces                             # 워크스페이스 목록
cmux current-workspace                           # 현재 워크스페이스
cmux new-workspace [--name <title>] [--description <text>] [--cwd <path>] [--command <text>]
                                                 # 새 워크스페이스 생성
cmux select-workspace --workspace <id|ref>       # 워크스페이스 전환
cmux close-workspace --workspace <id|ref>        # 워크스페이스 닫기
cmux rename-workspace [--workspace <id|ref>] <title>
                                                 # 워크스페이스 이름 변경
cmux reorder-workspace --workspace <id|ref> (--index <n> | --before <id> | --after <id>)
                                                 # 워크스페이스 순서 변경
```

---

## Pane Management (Splits)

```bash
cmux new-split <left|right|up|down> [--workspace <id|ref>] [--surface <id|ref>]
    # 현재 또는 지정된 surface에서 분할 생성
    # 출력: OK surface:N workspace:M
    # V2 RPC: surface.split

cmux list-panes [--workspace <id|ref>]           # pane 목록
cmux focus-pane --pane <id|ref> [--workspace <id|ref>]
                                                 # pane 포커스
cmux new-pane [--type terminal|browser] [--direction <dir>] [--workspace <id|ref>] [--url <url>]
                                                 # 새 pane 생성
cmux resize-pane --pane <id|ref> (-L|-R|-U|-D) [--amount <n>]
                                                 # pane 크기 조정
cmux swap-pane --pane <id|ref> --target-pane <id|ref>
                                                 # pane 위치 교체
```

---

## Surface (Tab) Management

```bash
cmux list-pane-surfaces [--workspace <id|ref>] [--pane <id|ref>]
                                                 # pane 내 surface 목록
cmux list-panels [--workspace <id|ref>]          # 전체 surface 목록 (alias)
cmux new-surface [--type terminal|browser] [--pane <id|ref>] [--workspace <id|ref>] [--url <url>]
                                                 # 새 surface 생성
cmux focus-panel --panel <id|ref> [--workspace <id|ref>]
                                                 # surface 포커스
cmux close-surface [--surface <id|ref>] [--workspace <id|ref>]
                                                 # surface 닫기
cmux rename-tab [--workspace <id|ref>] [--tab <id|ref>] [--surface <id|ref>] <title>
                                                 # surface 탭 이름 변경
cmux move-surface --surface <id|ref> [--pane <id|ref>] [--before <id> | --after <id> | --index <n>]
                                                 # surface를 다른 pane으로 이동
cmux reorder-surface --surface <id|ref> (--index <n> | --before <id> | --after <id>)
                                                 # surface 순서 변경
cmux drag-surface-to-split --surface <id|ref> <left|right|up|down>
                                                 # surface를 새 split으로 드래그
cmux break-pane [--surface <id|ref>]             # surface를 독립 workspace로 분리
cmux join-pane --target-pane <id|ref> [--surface <id|ref>]
                                                 # surface를 대상 pane에 합류
cmux refresh-surfaces                            # surface 상태 새로고침
cmux surface-health [--workspace <id|ref>]       # surface 건강 상태
cmux trigger-flash [--workspace <id|ref>] [--surface <id|ref>]
                                                 # surface 시각적 강조
```

---

## Terminal I/O

```bash
cmux read-screen [--workspace <id|ref>] [--surface <id|ref>] [--scrollback] [--lines <n>]
    # 터미널 화면 내용 읽기
    # --scrollback: 스크롤백 버퍼 포함
    # --lines N: 마지막 N줄만

cmux send [--workspace <id|ref>] [--surface <id|ref>] <text>
    # 텍스트 전송. \n/\t는 셸 터미널에서만 엔터/탭으로 해석되고,
    # Claude Code/Codex 같은 TUI REPL은 별도의 enter 키 이벤트를
    # 받아야 submit된다. 따라서 프롬프트 전달 시 항상 아래 pair 사용:
    #   cmux send <text>
    #   cmux send-key enter

cmux send-key [--workspace <id|ref>] [--surface <id|ref>] <key>
    # 키 이벤트 전송 (enter, ctrl+c, escape 등)
    # send 뒤에 반드시 호출해야 TUI에서 메시지가 실제로 전송됨.

cmux send-panel --panel <id|ref> [--workspace <id|ref>] <text>
    # panel(surface) 지정 텍스트 전송. send와 마찬가지로 뒤에
    # send-key-panel enter 를 붙여 submit 해야 한다.

cmux send-key-panel --panel <id|ref> [--workspace <id|ref>] <key>
    # panel(surface) 지정 키 전송
```

---

## Hierarchy Inspection

```bash
cmux tree [--all] [--workspace <id|ref|index>] [--json]
    # 전체 계층 구조 표시 (V2: system.tree)
    # --json: JSON 형식 출력
    # --all: 모든 workspace (기본: 현재 workspace만)
```

### tree --json 응답 구조

```json
{
  "windows": [{
    "ref": "window:1",
    "current": true,
    "workspaces": [{
      "ref": "workspace:1",
      "title": "my-workspace",
      "selected": true,
      "panes": [{
        "ref": "pane:1",
        "focused": true,
        "surfaces": [{
          "ref": "surface:1",
          "type": "terminal",
          "title": "bash",
          "selected": true,
          "here": true,
          "tty": "/dev/pts/0"
        }]
      }]
    }]
  }],
  "caller": {
    "workspace_ref": "workspace:1",
    "surface_ref": "surface:1"
  }
}
```

**핵심 필드:**
- `here: true` — 호출자(Claude)가 실행 중인 surface
- `caller` — 호출자의 workspace/surface ref 직접 제공
- `title` — `rename-tab`으로 설정한 이름, 에이전트 감지에 사용
- `selected: true` — 현재 선택된 workspace
- `focused: true` — 현재 포커스된 pane

---

## Notifications & Status

```bash
cmux notify --title <text> [--subtitle <text>] [--body <text>] [--workspace <id>] [--surface <id>]
                                                 # 알림 생성
cmux list-notifications                          # 알림 목록
cmux clear-notifications                         # 알림 제거
```

---

## Browser Integration

```bash
# 열기
cmux browser open [url]                          # 새 브라우저 split 열기
cmux browser open-split [url]                    # alias

# 네비게이션
cmux browser [surface] navigate <url> [--snapshot-after]
cmux browser [surface] back|forward|reload [--snapshot-after]
cmux browser [surface] url|get-url               # 현재 URL

# DOM 인터랙션
cmux browser [surface] click|dblclick|hover|focus|check|uncheck <selector> [--snapshot-after]
cmux browser [surface] type <selector> <text> [--snapshot-after]
cmux browser [surface] fill <selector> [text] [--snapshot-after]
cmux browser [surface] press <key> [--snapshot-after]
cmux browser [surface] select <selector> <value> [--snapshot-after]
cmux browser [surface] scroll [--selector <css>] [--dx N] [--dy N] [--snapshot-after]

# 검사
cmux browser [surface] snapshot [--interactive|-i] [--cursor] [--compact] [--max-depth N] [--selector <css>]
cmux browser [surface] screenshot [--out <path>] [--json]
cmux browser [surface] get <url|title|text|html|value|attr|count|box|styles> [...]
cmux browser [surface] is <visible|enabled|checked> <selector>
cmux browser [surface] find <role|text|label|placeholder|alt|title|testid|first|last|nth> ...

# 대기
cmux browser [surface] wait [--selector <css>] [--text <text>] [--url-contains <text>] [--load-state <state>] [--timeout-ms <ms>]

# JavaScript
cmux browser [surface] eval <script>
cmux browser [surface] addscript <script>
cmux browser [surface] addinitscript <script>
cmux browser [surface] addstyle <css>

# 상태 관리
cmux browser [surface] cookies <get|set|clear> [...]
cmux browser [surface] storage <local|session> <get|set|clear> [...]
cmux browser [surface] state <save|load> <path>
cmux browser [surface] console <list|clear>
cmux browser [surface] errors <list|clear>

# 탭 관리
cmux browser [surface] tab <new|list|switch|close|index> [...]

# 다이얼로그 & 다운로드
cmux browser [surface] dialog <accept|dismiss> [text]
cmux browser [surface] download [wait] [--path <path>] [--timeout-ms <ms>]

# 프레임
cmux browser [surface] frame <selector|main>
```

---

## SSH Remote

```bash
cmux ssh <destination> [--name <title>] [--port <n>] [--identity <path>] [--ssh-option <opt>] [--no-focus]
    # 원격 SSH 워크스페이스 생성 (자동 재연결 지원)
cmux remote-daemon-status [--os darwin|linux] [--arch arm64|amd64]
    # 원격 데몬 상태 확인
```

---

## Agent Integration

```bash
cmux claude-teams [claude-args...]               # Claude Code 팀 통합
cmux claude-hook <session-start|stop|notification> [--workspace ID] [--surface ID]
                                                 # Claude 훅 이벤트 처리
cmux codex <install-hooks|uninstall-hooks>       # Codex 훅 관리
cmux omo [opencode-args...]                      # OMO 에이전트
cmux omx [omx-args...]                           # OMX 에이전트
cmux omc [omc-args...]                           # OMC 에이전트
```

---

## tmux Compatibility

```bash
cmux capture-pane [--scrollback] [--lines N]     # read-screen alias
cmux pipe-pane --command <cmd>                   # 출력 파이프
cmux wait-for [-S|--signal] <name> [--timeout <sec>]
                                                 # 시그널 대기/전송
cmux next-window | previous-window | last-window # 윈도우 네비게이션
cmux last-pane                                   # 마지막 pane 포커스
cmux find-window [--content] [--select] <query>  # 윈도우/내용 검색
cmux respawn-pane [--command <cmd>]              # pane 셸 재시작
cmux display-message [-p|--print] <text>         # 메시지 표시
```

---

## Clipboard & Buffer

```bash
cmux set-buffer [--name <name>] <text>           # 클립보드 버퍼 설정
cmux list-buffers                                # 버퍼 목록
cmux paste-buffer [--name <name>]                # 버퍼 붙여넣기
```

---

## Hooks

```bash
cmux set-hook [--list]                           # 등록된 훅 목록
cmux set-hook <event> <command>                  # 훅 등록
cmux set-hook --unset <event>                    # 훅 제거
```

---

## Utilities

```bash
cmux markdown [open] <path>                      # 마크다운 파일 뷰어
cmux reload-config                               # 설정 파일 리로드
cmux shortcuts                                   # 단축키 목록
cmux set-app-focus <active|inactive|clear>       # 앱 포커스 오버라이드
```

---

## V2 JSON-RPC Protocol

소켓 통신용 JSON-RPC 프로토콜. 한 줄에 하나의 JSON 요청.

### Request

```json
{"id":"req-1","method":"workspace.list","params":{}}
```

### Response

```json
{"id":"req-1","ok":true,"result":{...}}
```

### Error

```json
{"id":"req-1","ok":false,"error":{"code":"not_found","message":"workspace not found"}}
```

### Method Mapping (CLI → V2 RPC)

| CLI Command | V2 Method |
|-------------|-----------|
| `tree --json` | `system.tree` |
| `identify` | `system.identify` |
| `list-workspaces` | `workspace.list` |
| `new-workspace` | `workspace.create` |
| `select-workspace` | `workspace.select` |
| `close-workspace` | `workspace.close` |
| `current-workspace` | `workspace.current` |
| `list-panes` | `pane.list` |
| `focus-pane` | `pane.focus` |
| `list-pane-surfaces` | `pane.surfaces` |
| `new-split` | `surface.split` |
| `new-surface` | `surface.create` |
| `close-surface` | `surface.close` |
| `focus-panel` | `surface.focus` |
| `read-screen` | `surface.read_text` |
| `send` | `surface.send_text` |
| `send-key` | `surface.send_key` |
| `notify` | `notification.create` |
| `browser open` | `browser.open_split` |
| `browser navigate` | `browser.navigate` |

### Python Socket Client Example

```python
import json, os, socket

SOCKET_PATH = os.environ.get("CMUX_SOCKET_PATH",
    os.path.expanduser("~/Library/Application Support/cmux/cmux.sock"))

def rpc(method, params=None, req_id=1):
    payload = {"id": req_id, "method": method, "params": params or {}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(payload).encode("utf-8") + b"\n")
        return json.loads(sock.recv(65536).decode("utf-8"))

# Usage
print(rpc("workspace.list"))
print(rpc("system.tree"))
print(rpc("surface.split", {"direction": "right"}))
```
