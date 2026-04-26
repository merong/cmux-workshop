# project-view Architecture (redis-chat-ui)

## Component map

```
┌──────────────────────────────────────────────────────────────────────┐
│  Producers (Claude Code hooks)                                       │
│   • cmux-workshop PreToolUse / PostToolUse hooks                     │
│   • prompt-submit / stop / idle session hooks                        │
│   • XADD cmux:hooks  +  HSET <detail_hash> <detail_ref> <full_json>  │
└───────────────────────┬──────────────────────────────────────────────┘
                        │
                        ▼
                  ┌─────────────┐
                  │ Redis 6379  │  Stream: cmux:hooks  (default)
                  │             │  Hash:   <detail_hash>     (enrichment)
                  └──────┬──────┘
                         │ XREVRANGE / XREAD / HGET
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ runtime/server.js  ── express + ws (single process)                  │
│   • static  → dist/index.html (built React bundle)                   │
│   • REST    → /api/workspaces, /api/messages, /api/surfaces          │
│   • stream  → /ws  (XREAD + lib/parser.js normalize → JSON frame)    │
│   • cmuxRpc → execFile("cmux","rpc", …) for workspace metadata       │
└───────────────────────┬──────────────────────────────────────────────┘
                        │ HTTP + WebSocket
                        ▼
┌──────────────────────────────────────────────────────────────────────┐
│ runtime/client (React 19, built once with vite)                      │
│   • Workspace list (Redis stream + cmux meta merge)                  │
│   • Chat timeline (prompt-submit, pre/post-tool-use, stop/idle)      │
│   • Auto-scroll, markdown render (utils/markdown.js)                 │
└──────────────────────────────────────────────────────────────────────┘
```

## Process lifecycle

| Step | Owner | Foreground? |
|------|-------|-------------|
| `check-deps.sh` | `start.sh` | yes (blocking) |
| `npm run build` (only when `dist/index.html` is missing) | `start.sh` | yes |
| `node server.js` (express + ws + Redis stream consumer) | `start.sh` (nohup) | no — PID `/tmp/cmux-workshop-web.pid` |
| Readiness probe (`curl`) | `start.sh` | yes (≤ 60s) |
| `open http://localhost:11573` (or `$CMUX_WORKSHOP_SERVER_PORT`) | calling agent (Claude) | yes |

## Why a single server?

`redis-chat-ui` is built to run as a single express process in production: vite is only invoked at build time to emit `dist/`, and `server.js` then both serves the static bundle and handles `/api/*` + `/ws`. The launcher therefore has just one node child to track instead of vite + express in parallel — simpler PID ownership, one log file, one port.

## Why a Redis Stream?

- Append-only log with backpressure-safe replay → the WebSocket layer can resume from the last seen stream id without missing or duplicating messages.
- Lets multiple consumers (this dashboard, archival jobs, downstream agents) read the same hook history independently.
- Persists across server restarts; old entries are trimmed by `XTRIM ~ MAXLEN` on a schedule defined in `server.js`.

## Ports

| Port | Service | Override env var | Notes |
|------|---------|------------------|-------|
| 11573 | Express + WebSocket (also serves React bundle) | `CMUX_WORKSHOP_SERVER_PORT` (or legacy `PORT`) | **Open this in the browser** |
| 6379 | Redis | `REDIS_URL` | Standard local install |

The default is deliberately uncommon to dodge collisions with other Express dev stacks (3000/3001/8080). `start.sh` reclaims the port from a foreign listener (SIGTERM, then SIGKILL) before booting; export the env var to coexist instead.

## File responsibilities

| File | Responsibility |
|------|----------------|
| `runtime/server.js` | Express + ws server: REST, `/ws`, stream consumer, detail enrichment, cmux RPC, periodic XTRIM |
| `runtime/lib/parser.js` | Convert Redis flat field array → object; subcommand → UI hint mapping |
| `runtime/vite.config.js` | Build-time only: `root: client/`, `outDir: ../dist`; dev proxy for `/api` and `/ws` (only used when running `npm run dev` manually) |
| `runtime/client/src/App.jsx` | React root: workspace selector + chat view + WebSocket subscription |
| `runtime/client/src/hooks/useWebSocket.js` | Reconnecting WS client, replay on disconnect |
| `runtime/client/src/utils/messagePresentation.js` | Subcommand → renderer mapping for the chat timeline |
