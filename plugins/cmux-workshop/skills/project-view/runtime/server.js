const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const Redis = require("ioredis");
const path = require("path");
const fs = require("fs");
const { execFile } = require("child_process");
const { normalizeMessage } = require("./lib/parser");

const STREAM_KEY = process.env.STREAM_KEY || "cmux:hooks";
const PORT = process.env.PORT || 3000;
const REDIS_URL = process.env.REDIS_URL || "redis://127.0.0.1:6379";
const STREAM_MAXLEN = parseInt(process.env.STREAM_MAXLEN || "10000", 10);

// Producer(cmux hooks)가 Stream에 쓸 때 preview를 200자로 자르므로,
// stop/idle + pre-tool-use 이벤트는 detail Hash의 전문을 읽어 보강한다.
const RESPONSE_PREVIEW_MAX = 64 * 1024;
const TOOL_INPUT_MAX = 4 * 1024;
const TOOL_INPUT_FIELD_MAX = 512; // Edit.old_string / Write.content 같은 거대 필드는 필드 단위 preview

const app = express();
const server = http.createServer(app);

// Static files — serve React build from dist/
const distPath = path.join(__dirname, "dist");
if (!fs.existsSync(path.join(distPath, "index.html"))) {
  console.error(`dist/index.html not found at ${distPath}. Run "npm run build" first.`);
  process.exit(1);
}
app.use(express.static(distPath));
app.use(express.json());

// Redis clients
const redis = new Redis(REDIS_URL);

// --- Detail enrichment ---
// Stream preview(200자)로는 부족한 경우 detail Hash에서 전문을 읽어 보강한다.
function compactToolInput(input) {
  if (!input || typeof input !== "object") return null;
  const compact = {};
  for (const [k, v] of Object.entries(input)) {
    if (typeof v === "string") {
      compact[k] = v.length > TOOL_INPUT_FIELD_MAX ? v.slice(0, TOOL_INPUT_FIELD_MAX) : v;
    } else if (v === null || typeof v === "number" || typeof v === "boolean") {
      compact[k] = v;
    } else if (Array.isArray(v)) {
      compact[k] = `[array×${v.length}]`;
    } else if (typeof v === "object") {
      compact[k] = `{${Object.keys(v).slice(0, 8).join(",")}}`;
    }
  }
  let json = JSON.stringify(compact);
  if (json.length > TOOL_INPUT_MAX) json = json.slice(0, TOOL_INPUT_MAX);
  return json;
}

async function enrichFromDetail(msg) {
  if (!msg.detail_hash || !msg.detail_ref) return msg;
  const needsResponse =
    (msg.subcommand === "stop" || msg.subcommand === "idle") &&
    (!msg.response_preview || msg.response_preview.length >= 200);
  const needsTool = msg.subcommand === "pre-tool-use" && !msg.tool_input;
  if (!needsResponse && !needsTool) return msg;

  try {
    const data = await redis.hget(msg.detail_hash, msg.detail_ref);
    if (!data) return msg;
    const parsed = JSON.parse(data);
    if (needsResponse) {
      const full = parsed.last_assistant_message || parsed.lastAssistantMessage;
      if (typeof full === "string" && full.length > 0) {
        msg.response_preview = full.slice(0, RESPONSE_PREVIEW_MAX);
      }
    }
    if (needsTool) {
      const compacted = compactToolInput(parsed.tool_input);
      if (compacted) msg.tool_input = compacted;
    }
  } catch {
    // Hash 없음/JSON 파싱 실패 → 원본 msg 유지
  }
  return msg;
}

// --- REST API ---

// --- cmux RPC helper ---
// cmux daemon이 간헐적으로 busy/timeout 응답을 줄 수 있어 소량의 retry를 둔다.
function cmuxRpc(method, params, retries = 2) {
  return new Promise((resolve, reject) => {
    const run = (left) => {
      execFile(
        "cmux",
        ["rpc", method, JSON.stringify(params)],
        { timeout: 5000 },
        (err, stdout) => {
          if (err) {
            if (left > 0) return setTimeout(() => run(left - 1), 250);
            return reject(err);
          }
          try {
            resolve(JSON.parse(stdout));
          } catch {
            resolve(null);
          }
        }
      );
    };
    run(retries);
  });
}

// GET /api/workspaces — Redis stream 데이터 + cmux 메타데이터 병합
app.get("/api/workspaces", async (req, res) => {
  try {
    // 1. Redis stream에서 활동 데이터 수집
    const entries = await redis.xrevrange(STREAM_KEY, "+", "-", "COUNT", 500);
    const workspaceMap = new Map();

    for (const [id, fields] of entries) {
      const msg = normalizeMessage(id, fields);
      if (!workspaceMap.has(msg.workspace_id)) {
        workspaceMap.set(msg.workspace_id, {
          workspace_id: msg.workspace_id,
          cwd: msg.cwd,
          hostname: msg.hostname,
          last_activity: msg.timestamp,
          surface_ids: new Set(),
        });
      }
      workspaceMap.get(msg.workspace_id).surface_ids.add(msg.surface_id);
    }

    // 2. cmux RPC로 workspace 메타데이터 가져오기
    let cmuxMeta = new Map();
    try {
      const rpcResult = await cmuxRpc("workspace.list", {});
      if (rpcResult && rpcResult.workspaces) {
        for (const ws of rpcResult.workspaces) {
          cmuxMeta.set(ws.id, {
            title: ws.title || "",
            description: ws.description || "",
            custom_color: ws.custom_color || null,
            selected: ws.selected || false,
            pinned: ws.pinned || false,
            listening_ports: ws.listening_ports || [],
            ref: ws.ref || "",
            index: ws.index,
          });
        }
      }
    } catch (e) {
      // cmux not available — continue without metadata
    }

    // 3. cmux RPC로 각 workspace의 surface 목록 가져오기
    let cmuxSurfaces = new Map();
    for (const [wsId] of cmuxMeta) {
      try {
        const surfResult = await cmuxRpc("surface.list", { workspace_id: wsId });
        const surfaces = surfResult?.surfaces || surfResult?.panels || [];
        cmuxSurfaces.set(wsId, surfaces.map((s) => ({
          id: s.id,
          ref: s.ref,
          title: s.title || "",
          type: s.type || "terminal",
          focused: s.focused || false,
        })));
      } catch {
        // skip
      }
    }

    // 4. 병합: Redis 활동 데이터 + cmux 메타데이터
    const workspaces = Array.from(workspaceMap.values()).map((w) => {
      const meta = cmuxMeta.get(w.workspace_id) || {};
      const surfaces = cmuxSurfaces.get(w.workspace_id) || [];
      return {
        ...w,
        surface_ids: Array.from(w.surface_ids),
        // cmux metadata
        title: meta.title || "",
        description: meta.description || "",
        custom_color: meta.custom_color || null,
        selected: meta.selected || false,
        pinned: meta.pinned || false,
        listening_ports: meta.listening_ports || [],
        ref: meta.ref || "",
        cmux_surfaces: surfaces,
      };
    });

    res.json(workspaces);
  } catch (err) {
    console.error("GET /api/workspaces error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/history — 특정 workspace의 히스토리
app.get("/api/history", async (req, res) => {
  const { workspace_id, count = "100" } = req.query;
  if (!workspace_id) {
    return res.status(400).json({ error: "workspace_id required" });
  }

  try {
    const entries = await redis.xrevrange(STREAM_KEY, "+", "-", "COUNT", 1000);
    const messages = [];

    for (const [id, fields] of entries) {
      const msg = normalizeMessage(id, fields);
      if (msg.workspace_id === workspace_id) {
        messages.push(msg);
        if (messages.length >= parseInt(count, 10)) break;
      }
    }

    await Promise.all(messages.map(enrichFromDetail));

    // 시간순 정렬 (오래된 것 먼저)
    messages.reverse();
    res.json(messages);
  } catch (err) {
    console.error("GET /api/history error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/events/detail — Hash에서 상세 데이터 온디맨드 조회
app.get("/api/events/detail", async (req, res) => {
  const { hash, ref } = req.query;

  if (!hash || !ref) {
    return res.status(400).json({ error: "hash and ref parameters required" });
  }

  // 키 패턴 검증: cmux:ws: 접두사만 허용
  if (!hash.startsWith("cmux:ws:")) {
    return res.status(400).json({ error: "Invalid key pattern" });
  }

  try {
    const data = await redis.hget(hash, ref);
    if (!data) {
      return res.status(404).json({ error: "Detail not found" });
    }

    try {
      res.json({ detail: JSON.parse(data) });
    } catch {
      res.json({ detail: data });
    }
  } catch (err) {
    console.error("GET /api/events/detail error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/commands — cmux CLI 명령 실행
const ALLOWED_COMMANDS = ["screenshot", "status", "list-workspaces", "list-surfaces"];

app.post("/api/commands", (req, res) => {
  const { command, args = [] } = req.body;

  if (!command || !ALLOWED_COMMANDS.includes(command)) {
    return res.status(403).json({
      error: "Command not allowed",
      allowed: ALLOWED_COMMANDS,
    });
  }

  // 인자 안전성 검증: 쉘 메타 문자 차단
  const safeArgs = args.filter((a) => typeof a === "string" && !/[;&|`$(){}]/.test(a));

  execFile("cmux", [command, ...safeArgs], { timeout: 10000 }, (err, stdout, stderr) => {
    if (err) {
      return res.status(500).json({ error: err.message, stderr });
    }
    res.json({ output: stdout, stderr });
  });
});

// --- WebSocket ---

const wss = new WebSocketServer({ server });

// workspace_id → Set<ws> 매핑
const subscriptions = new Map();

wss.on("connection", (ws) => {
  ws._subscribedWorkspace = null;

  ws.on("message", async (raw) => {
    try {
      const msg = JSON.parse(raw);

      if (msg.type === "subscribe" && msg.workspace_id) {
        // 기존 구독 해제
        if (ws._subscribedWorkspace) {
          const oldSet = subscriptions.get(ws._subscribedWorkspace);
          if (oldSet) {
            oldSet.delete(ws);
            if (oldSet.size === 0) subscriptions.delete(ws._subscribedWorkspace);
          }
        }
        // 새 구독
        ws._subscribedWorkspace = msg.workspace_id;
        if (!subscriptions.has(msg.workspace_id)) {
          subscriptions.set(msg.workspace_id, new Set());
        }
        subscriptions.get(msg.workspace_id).add(ws);
      }

      // get_detail: Hash에서 상세 데이터 조회
      // NOTE: Unused by the current web client (REST-only via /api/events/detail).
      // Retained for external WS consumers and future reuse.
      if (msg.type === "get_detail" && msg.detail_hash && msg.detail_ref) {
        if (!msg.detail_hash.startsWith("cmux:ws:")) {
          ws.send(JSON.stringify({ type: "detail", detail_ref: msg.detail_ref, data: null, error: "Invalid key" }));
          return;
        }
        try {
          const data = await redis.hget(msg.detail_hash, msg.detail_ref);
          const parsed = data ? JSON.parse(data) : null;
          ws.send(JSON.stringify({ type: "detail", detail_ref: msg.detail_ref, data: parsed }));
        } catch (err) {
          ws.send(JSON.stringify({ type: "detail", detail_ref: msg.detail_ref, data: null, error: err.message }));
        }
      }
    } catch {
      // ignore malformed messages
    }
  });

  ws.on("close", () => {
    if (ws._subscribedWorkspace) {
      const set = subscriptions.get(ws._subscribedWorkspace);
      if (set) {
        set.delete(ws);
        if (set.size === 0) subscriptions.delete(ws._subscribedWorkspace);
      }
    }
  });
});

function broadcast(workspaceId, message) {
  const clients = subscriptions.get(workspaceId);
  if (!clients) return;
  const payload = JSON.stringify({ type: "event", data: message });
  for (const ws of clients) {
    if (ws.readyState === 1) {
      ws.send(payload);
    }
  }
}

// --- Redis Stream Consumer ---

async function consumeStream() {
  let lastId = "$";
  const streamRedis = new Redis(REDIS_URL);

  while (true) {
    try {
      const result = await streamRedis.xread(
        "BLOCK", 5000, "COUNT", 100, "STREAMS", STREAM_KEY, lastId
      );
      if (!result) continue;

      const [, entries] = result[0];
      for (const [id, fields] of entries) {
        lastId = id;
        const msg = normalizeMessage(id, fields);
        await enrichFromDetail(msg);
        broadcast(msg.workspace_id, msg);
      }
    } catch (err) {
      console.error("Stream read error:", err.message);
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
}

// --- Stream Trimming (주기적) ---

async function trimStream() {
  if (STREAM_MAXLEN <= 0) return;
  try {
    await redis.xtrim(STREAM_KEY, "MAXLEN", "~", STREAM_MAXLEN);
  } catch (err) {
    console.error("Stream trim error:", err.message);
  }
}

// SPA fallback — serve index.html for non-API routes
app.get("/{*splat}", (req, res, next) => {
  if (req.path.startsWith("/api/")) return next();
  const indexPath = path.join(distPath, "index.html");
  res.sendFile(indexPath);
});

// --- Start ---

server.listen(PORT, () => {
  console.log(`Redis Chat UI running on http://localhost:${PORT}`);
  console.log(`Stream: ${STREAM_KEY}, Redis: ${REDIS_URL}`);
  consumeStream();

  // 1시간 주기 Stream 트리밍
  trimStream();
  setInterval(trimStream, 3600000);
});
