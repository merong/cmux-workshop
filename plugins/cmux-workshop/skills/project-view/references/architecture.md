# project-view Architecture

## Component map

```
┌──────────────────────────────────────────────────────────────────────┐
│                          cmux app (macOS)                            │
│   Unix Domain Socket: ~/Library/Application Support/cmux/cmux.sock   │
└───────────────────────┬──────────────────────────────────────────────┘
                        │ JSON-RPC (intercepted)
┌───────────────────────▼──────────────────────────────────────────────┐
│ runtime/proxy.py  ── transparent socket proxy                        │
│   • cmux.sock        ←→ clients (Claude Code, scripts, GUI)          │
│   • cmux-real.sock   ←→ cmux app (renamed by cmux-proxy.sh inject)   │
│   • XADD cmux:requests / cmux:responses to Redis Streams             │
└───────────────────────┬──────────────────────────────────────────────┘
                        │
                        ▼
                  ┌─────────────┐
                  │ Redis 6379  │  Streams: cmux:requests, cmux:responses,
                  └──────┬──────┘            cmux:terminal_output
                         │
   ┌─────────────────────┴────────────────────────┐
   │                                              │
   ▼                                              ▼
┌──────────────────────┐               ┌──────────────────────────────┐
│ runtime/web/server   │               │ runtime/polling_monitor.py   │
│ (Express + Socket.io)│               │ • cmux read-screen polling   │
│ Port 11573 (default) │               │ • XADD cmux:terminal_output  │
│ • XREAD streams      │               └──────────────────────────────┘
│ • Push WS events     │
└──────────┬───────────┘
           │ Socket.io (init / traffic / stats)
           ▼
┌────────────────────────────────────────────┐
│ runtime/web/client (Vite + React)          │
│ Port 13331 (default) — opened in browser   │
│ Views: Dashboard, Traffic, Workspace,      │
│        Terminal, MethodsTable              │
└────────────────────────────────────────────┘
```

## Process lifecycle

| Step | Owner | Foreground? |
|------|-------|-------------|
| `check-deps.sh` | `start.sh` | yes (blocking) |
| `cmux-proxy.sh inject` | `start.sh` | yes (returns once proxy is detached) |
| `npm run dev` (Express + Vite) | `start.sh` (nohup) | no — PID `/tmp/cmux-workshop-web.pid` |
| `python3 polling_monitor.py` | `start.sh` (nohup) | no — PID `/tmp/cmux-workshop-polling.pid` |
| Readiness probe (`curl`) | `start.sh` | yes (≤ 60s) |
| `open http://localhost:13331` (or `$CMUX_WORKSHOP_WEB_PORT`) | calling agent (Claude) | yes |

## Why a proxy?

cmux exposes a JSON-RPC API over a Unix Domain Socket. The proxy renames the
real socket to `cmux-real.sock`, listens on the original path, and copies every
frame to Redis Streams while forwarding the bytes upstream. This is fully
transparent: clients (`cmux ping`, Claude Code skills, the GUI) need no
configuration change.

## Why Redis Streams?

- Append-only log with consumer groups → multiple viewers (web server,
  `monitor.py`, `consumer.py`) replay the same traffic without conflicts.
- Backpressure-safe — slow consumers don't block the proxy.
- Persists across restarts of any single component.

## Ports

| Port | Service | Override env var | Notes |
|------|---------|------------------|-------|
| 13331 | Vite dev server (React UI) | `CMUX_WORKSHOP_WEB_PORT` | **Open this in the browser** |
| 11573 | Express + Socket.io | `CMUX_WORKSHOP_SERVER_PORT` (or legacy `PORT`) | Internal; Vite proxies to it |
| 6379 | Redis | — | Standard local install |

The defaults are deliberately uncommon to dodge collisions with other Vite/Express dev stacks. `start.sh` reclaims either port from a foreign listener (SIGTERM, then SIGKILL) before booting the web stack; export the env vars above to coexist instead.

## File responsibilities

| File | Responsibility |
|------|----------------|
| `runtime/proxy.py` | asyncio socket proxy → Redis Streams |
| `runtime/cmux-proxy.sh` | inject / status / stop / install (LaunchAgent) |
| `runtime/polling_monitor.py` | call `cmux read-screen` periodically; emit terminal frames |
| `runtime/monitor.py` | optional CLI viewer of the same streams |
| `runtime/consumer.py` | example Redis Consumer Group worker |
| `runtime/web/server/index.js` | Express + Socket.io server; reads streams, exposes WebSocket |
| `runtime/web/client/src/App.jsx` | React root with Sidebar + view switching |
| `runtime/web/client/src/hooks/useSocket.js` | Socket.io connection + event subscription |
