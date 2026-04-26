---
name: project-view
description: >
  Use this skill to launch the cmux Workshop monitor stack — a vendored,
  self-contained bundle of the cmux socket proxy, the Express + Socket.io
  server, the Vite/React dashboard, and the terminal polling monitor — and
  open the dashboard in the default browser. Trigger on "/project-view",
  "project view", "open cmux monitor", "start cmux dashboard", "launch cmux
  workshop monitor", "cmux monitor 열어", "cmux 모니터 시작", "프로젝트 뷰",
  "cmux 대시보드 켜". Do NOT trigger for general cmux CLI control (use the
  `cmux` skill for that). If cmux, Redis, Node.js, or Python redis is missing,
  surface the dependency guidance produced by check-deps.sh to the user
  instead of trying to install anything yourself.
version: 0.1.2
---

# project-view — cmux Workshop Monitor Launcher

This skill bundles `cmux-monitor` as part of the cmux-workshop plugin. A single invocation:

1. Verifies dependencies (cmux app, Redis server, Node.js ≥ 18, Python `redis`, web `node_modules`).
2. Injects the cmux socket proxy so every JSON-RPC call is mirrored into Redis Streams.
3. Reclaims the dashboard ports if a foreign process holds them, then starts the Express + Socket.io server (port `11573`) and the Vite dev server (port `13331`).
4. Starts `polling_monitor.py` so the dashboard's Terminal View is populated.
5. Waits until `http://localhost:13331` answers, then opens it in the default browser.

The skill is **idempotent**. Re-running it while everything is already up is a no-op that just reopens the browser.

### Default ports and overrides

The defaults are deliberately uncommon to dodge collisions with other Vite/Express dev stacks running on the host:

| Component | Env var | Default |
|---|---|---|
| Vite dev server (dashboard URL) | `CMUX_WORKSHOP_WEB_PORT` | `13331` |
| Express + Socket.io server | `CMUX_WORKSHOP_SERVER_PORT` | `11573` |

If either port is held by a process that is **not** the project-view runtime tracked via `/tmp/cmux-workshop-web.pid`, `start.sh` automatically reclaims it (SIGTERM, then SIGKILL after a short grace period). Set the env vars above instead if you want to coexist with that process.

## How to invoke

When the user asks to launch / open the cmux monitor (typically via `/project-view`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-view/scripts/start.sh"
```

`start.sh` prints progress on stderr and a single sentinel line on stdout when ready:

```
READY: http://localhost:13331
```

When you observe that line, immediately open the URL:

```bash
open http://localhost:13331
```

If `CMUX_WORKSHOP_WEB_PORT` is exported, the URL printed in the sentinel reflects the override.

If `start.sh` exits non-zero, **do not retry automatically**. Surface the dependency guidance it printed to the user verbatim and ask them to install / start the missing piece.

## What lives where

| Path (relative to skill root) | Role |
|---|---|
| `scripts/start.sh` | Entry point — orchestrates proxy + web + polling, waits for readiness |
| `scripts/stop.sh` | Stop entry point — kills owned launcher processes, restores proxy, cleans logs |
| `scripts/check-deps.sh` | Pre-flight check; exits non-zero with installation hints |
| `scripts/helpers.sh` | Shared logging / PID file helpers |
| `runtime/cmux-proxy.sh` | Vendored proxy controller (`inject` / `status` / `stop`) |
| `runtime/proxy.py`, `monitor.py`, `polling_monitor.py`, `consumer.py` | Vendored Python services |
| `runtime/web/` | Vendored Express server + Vite/React dashboard |
| `references/architecture.md` | Data-flow diagram and component overview |
| `references/troubleshooting.md` | Common failure modes and fixes |

## Lifecycle

Start the monitor with `/project-view` or:

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
[ -S "${CMUX_SOCKET_PATH:-$HOME/Library/Application Support/cmux/cmux.sock}" ] || echo "cmux app not running"
redis-cli ping >/dev/null 2>&1 || echo "Redis not running"
```

If neither responds, tell the user to start cmux and `brew services start redis` before retrying.
