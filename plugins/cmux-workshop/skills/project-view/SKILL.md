---
name: project-view
description: >
  Use this skill to launch the cmux Workshop project view — a vendored copy of
  the redis-chat-ui dashboard that consumes the `cmux:hooks` Redis stream
  (Claude Code hook events: prompt-submit, pre-tool-use, post-tool-use, stop,
  idle) and renders them as a workspace-grouped chat timeline. Trigger on
  "/project-view", "project view", "project view 실행", "open project view",
  "project view 켜", "프로젝트 뷰", "cmux 채팅 뷰", "claude code 활동 보기",
  "redis chat ui 켜". Do NOT trigger for general cmux CLI control (use the
  `cmux` skill for that). If Redis or Node.js is missing, surface the
  dependency guidance produced by check-deps.sh to the user instead of trying
  to install anything yourself.
version: 0.2.0
---

# project-view — cmux Workshop Project View

This skill bundles the [`redis-chat-ui`](https://github.com/merong/redis-chat-ui) dashboard as part of the cmux-workshop plugin. A single invocation:

1. Verifies dependencies (Redis server, Node.js ≥ 18, `runtime/node_modules`, optional `cmux` CLI for workspace metadata).
2. Reclaims the dashboard port if a foreign process holds it (SIGTERM → SIGKILL).
3. Builds the React bundle (`npm run build` → `dist/`) if it is missing.
4. Launches `node server.js` in the background — a single express + WebSocket process that serves the bundle, exposes REST under `/api/`, and streams hook events from Redis to the browser via `/ws`.
5. Waits until `http://localhost:11573` answers, then opens it in the default browser.

The skill is **idempotent**. Re-running it while everything is already up is a no-op that just reopens the browser.

### Default port and overrides

| Component | Env var | Default |
|---|---|---|
| Express + WebSocket server (dashboard URL) | `CMUX_WORKSHOP_SERVER_PORT` (or legacy `PORT`) | `11573` |
| Redis connection string | `REDIS_URL` | `redis://127.0.0.1:6379` |
| Redis stream key (Claude Code hooks) | `STREAM_KEY` | `cmux:hooks` |

If the port is held by a process that is **not** the project-view runtime tracked via `/tmp/cmux-workshop-web.pid`, `start.sh` automatically reclaims it. Set the env vars above instead if you want to coexist with that process.

## How to invoke

When the user asks to open the project view (typically via `/project-view`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-view/scripts/start.sh"
```

`start.sh` prints progress on stderr and a single sentinel line on stdout when ready:

```
READY: http://localhost:11573
```

When you observe that line, immediately open the URL:

```bash
open http://localhost:11573
```

If `CMUX_WORKSHOP_SERVER_PORT` is exported, the URL printed in the sentinel reflects the override.

If `start.sh` exits non-zero, **do not retry automatically**. Surface the dependency guidance it printed to the user verbatim and ask them to install / start the missing piece.

## What lives where

| Path (relative to skill root) | Role |
|---|---|
| `scripts/start.sh` | Entry point — port reclaim, ensure dist build, boot node server, wait for readiness |
| `scripts/stop.sh` | Stop entry point — kills only the launcher-owned PID file, cleans the log |
| `scripts/check-deps.sh` | Pre-flight check; exits non-zero with installation hints |
| `scripts/helpers.sh` | Shared logging / PID / port helpers |
| `runtime/server.js` | Vendored express + WebSocket server (`STREAM_KEY` consumer) |
| `runtime/vite.config.js` | Vendored vite config (used during `npm run build`) |
| `runtime/lib/parser.js` | Vendored stream-record normalization |
| `runtime/client/` | Vendored React 19 source — `App.jsx`, components, hooks, styles |
| `runtime/dist/` | Build output of `npm run build`; ignored by git |
| `runtime/node_modules/` | Dependencies installed via `npm install`; ignored by git |
| `references/architecture.md` | Data-flow diagram and component overview |
| `references/troubleshooting.md` | Common failure modes and fixes |

## Lifecycle

Start the project view with `/project-view` or:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-view/scripts/start.sh"
```

Stop it idempotently with `/project-view-stop` or:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-view/scripts/stop.sh"
```

PID and log files keep the `cmux-workshop-` prefix because they are owned by the plugin as a whole, not by this individual skill.

## Detection

Quick pre-check (the skill itself runs the full check):

```bash
redis-cli ping >/dev/null 2>&1 || echo "Redis not running"
node --version | grep -Eq 'v(1[89]|[2-9][0-9])' || echo "Node 18+ required"
```

If neither responds, tell the user to start Redis (`brew services start redis`) and install Node ≥ 18 (`brew install node`) before retrying.

## What the dashboard shows

`redis-chat-ui` consumes Claude Code hook events that producers write to `cmux:hooks` (subcommands: `prompt-submit`, `pre-tool-use`, `post-tool-use`, `stop`, `idle`). The UI:

- Groups messages by `workspace_id` and merges them with cmux RPC metadata (`workspace.list`, `surface.list`) for titles/colors when the cmux CLI is available.
- Streams new entries over WebSocket (`/ws`) with backpressure-safe replay from the last seen stream id.
- Enriches `stop`/`idle` previews and `pre-tool-use` payloads from the detail Hash referenced by `detail_hash`/`detail_ref` fields when the 200-char Stream preview is not enough.

The skill does not write to the Stream itself — that is the producer's responsibility (the `cmux-workshop` PreToolUse hook + Claude Code session lifecycle hooks).
