# project-view Troubleshooting

## Quick diagnostics

```bash
# Skill root (used in every snippet below)
SKILL=/Users/brian/works/agent/cmux-workshop/plugins/cmux-workshop/skills/project-view

# 1) Dependency status
bash "$SKILL/scripts/check-deps.sh"

# 2) Proxy status
bash "$SKILL/runtime/cmux-proxy.sh" status

# 3) Background process status
for f in /tmp/cmux-workshop-{web,polling}.pid; do
  [ -f "$f" ] && ps -p "$(cat "$f")" -o pid,etime,command 2>/dev/null
done

# 4) Recent logs
tail -n 50 /tmp/cmux-workshop-web.log
tail -n 50 /tmp/cmux-workshop-polling.log
tail -n 50 /tmp/cmux-proxy.log
```

## Symptom → Fix

### `check-deps.sh` reports "cmux app does not appear to be running"
The cmux GUI must be running so its socket exists. Open the cmux app, then re-run.

### `redis-cli ping` returns nothing
```bash
brew services start redis
# verify
redis-cli ping     # → PONG
```

### "Dashboard did not become ready in time"
1. Inspect `/tmp/cmux-workshop-web.log` — Vite usually prints the issue.
2. If startup fails before the web server launches, `start.sh` now prints the
   process holding port `5173` or `3001`:
   ```bash
   lsof -nP -iTCP:5173 -sTCP:LISTEN
   lsof -nP -iTCP:3001 -sTCP:LISTEN
   ```
   Stop the old service or run `/project-view-stop` if it is a stale
   cmux-workshop monitor. Do not edit the vendored Vite config in place.
3. If the log shows missing modules, install deps:
   ```bash
   (cd "$SKILL/runtime/web" && npm run install:all)
   ```

### Browser opens but shows "disconnected"
The Express server (port 3001) is down. Check `/tmp/cmux-workshop-web.log` for the
`server` half — `npm run dev` runs both Vite and Express via `web/scripts/dev.js`.
Restart with `/project-view-stop`, then re-run `/project-view`.

### Traffic log is empty
The proxy may have failed to inject. Run:
```bash
bash "$SKILL/runtime/cmux-proxy.sh" status
```
If it reports "not active", run `inject` again. If `cmux ping` still works
afterward, the proxy is sitting in front of the socket correctly.

### Terminal view is empty
That feed comes from `polling_monitor.py`. Confirm the PID is alive:
```bash
ps -p "$(cat /tmp/cmux-workshop-polling.pid)"
```
If the process exited, check `/tmp/cmux-workshop-polling.log` for the cause
(typically a missing `cmux read-screen` permission or no active surfaces).

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
cmux ping       # confirm cmux still responds after socket restoration
```

## When in doubt, restart from clean state

```bash
# stop everything
bash "$SKILL/scripts/stop.sh" || true

# start fresh
bash "$SKILL/scripts/start.sh"
```
