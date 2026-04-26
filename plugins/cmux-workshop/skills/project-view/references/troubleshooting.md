# project-view Troubleshooting (redis-chat-ui)

## Quick diagnostics

```bash
# Skill root (used in every snippet below)
SKILL=/Users/brian/works/agent/cmux-workshop/plugins/cmux-workshop/skills/project-view

# 1) Dependency status
bash "$SKILL/scripts/check-deps.sh"

# 2) Background process status
[ -f /tmp/cmux-workshop-web.pid ] && \
  ps -p "$(cat /tmp/cmux-workshop-web.pid)" -o pid,etime,command 2>/dev/null

# 3) Recent server log
tail -n 80 /tmp/cmux-workshop-web.log
```

## Symptom → Fix

### `check-deps.sh` reports "redis-cli not found" or PING fails
```bash
brew install redis
brew services start redis
redis-cli ping     # → PONG
```
If Redis is hosted elsewhere, point the launcher at it:
```bash
REDIS_URL=redis://your-host:6379/0 bash "$SKILL/scripts/start.sh"
```

### `check-deps.sh` reports "runtime/node_modules is missing"
```bash
( cd "$SKILL/runtime" && npm install )
```
This installs both runtime deps (`express`, `ioredis`, `marked`, `react`, `ws`) and the build-time devDeps (`vite`, `@vitejs/plugin-react`).

### "vite build failed"
The launcher only builds `dist/` when it does not already exist. If the build
itself errors out, run it manually so vite's full diagnostic reaches the
terminal:
```bash
( cd "$SKILL/runtime" && npm run build )
```
Common causes:
- Stale node_modules from a Node downgrade — `rm -rf node_modules && npm install`.
- Missing `index.html` in `client/` — repeat the re-vendor step from CLAUDE.md.

### "Dashboard did not become ready in time"
1. Inspect `/tmp/cmux-workshop-web.log` — `server.js` prints fatal errors there
   (Redis connection refused, port already bound, missing `dist/index.html`).
2. `start.sh` reclaims a foreign listener on the default port automatically
   (SIGTERM, then SIGKILL) before booting. If it bails anyway, the offending
   PID is logged. Verify manually with:
   ```bash
   lsof -nP -iTCP:11573 -sTCP:LISTEN     # express + websocket + static
   ```
   To pick a different port instead of killing the squatter, export
   `CMUX_WORKSHOP_SERVER_PORT` and re-run.

### Browser opens but the chat list is empty
The Stream is empty — no producer has written to `cmux:hooks` yet. Confirm:
```bash
redis-cli xlen cmux:hooks
redis-cli xrevrange cmux:hooks + - COUNT 5
```
If the stream key differs in your environment (e.g. namespaced per user),
override it:
```bash
STREAM_KEY=cmux:hooks:alice bash "$SKILL/scripts/start.sh"
```

### Workspace titles / colors are missing
`server.js` calls `cmux rpc workspace.list / surface.list` to enrich each
workspace card. When the cmux CLI is absent it silently drops to an
"unknown workspace" card. Symlink the CLI:
```bash
sudo ln -sf "/Applications/cmux.app/Contents/Resources/bin/cmux" /usr/local/bin/cmux
```
…then refresh the browser.

### WebSocket disconnects every few seconds
Inspect `/tmp/cmux-workshop-web.log` for `ECONNRESET` from ioredis — usually
caused by a Redis restart. The client (`useWebSocket.js`) reconnects with
back-off; if it spins, restart cleanly:
```bash
bash "$SKILL/scripts/stop.sh"
bash "$SKILL/scripts/start.sh"
```

### Stale PID file blocks restart
`start.sh` validates PID cwd/command ownership before reuse. If a PID file
points at a recycled PID owned by something else, `/project-view-stop` skips
the kill and removes the stale launcher PID file:
```bash
/project-view-stop
```

## Full shutdown

```bash
bash /Users/brian/works/agent/cmux-workshop/plugins/cmux-workshop/skills/project-view/scripts/stop.sh
```

## When in doubt, restart from a clean state

```bash
# stop everything
bash "$SKILL/scripts/stop.sh" || true

# start fresh
bash "$SKILL/scripts/start.sh"
```
