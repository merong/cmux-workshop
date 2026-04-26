import express from "express";
import { createServer } from "http";
import { Server } from "socket.io";
import Redis from "ioredis";
import { execSync } from "child_process";
import net from "net";
import path from "path";

const PORT =
  process.env.PORT ||
  process.env.CMUX_WORKSHOP_SERVER_PORT ||
  11573;
const REDIS_URL = process.env.REDIS_URL || "redis://localhost:6379/0";
const STREAM_REQ = "cmux:requests";
const STREAM_RES = "cmux:responses";
const STREAM_TERMINAL = "cmux:terminal_output";

// ── Redis 연결 ──

const redis = new Redis(REDIS_URL);
const redisSub = new Redis(REDIS_URL); // XREAD 전용

// ── cmux 소켓 경로 감지 ──

function detectSocketPath() {
  try {
    const out = execSync("cmux identify --json", { timeout: 5000 }).toString();
    return JSON.parse(out).socket_path;
  } catch {
    return "/tmp/cmux.sock";
  }
}

// ── cmux 소켓으로 JSON-RPC 호출 ──

function cmuxRpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const done = (fn, val) => {
      if (settled) return;
      settled = true;
      fn(val);
    };

    const sockPath = detectSocketPath();
    const client = net.createConnection(sockPath, () => {
      const msg = JSON.stringify({ id: `web-${Date.now()}`, method, params });
      client.write(msg + "\n");
    });

    let data = "";
    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        client.destroy();
        try {
          done(resolve, JSON.parse(data.trim()));
        } catch (e) {
          done(resolve, { ok: false, error: "parse_error" });
        }
      }
    });
    client.on("error", (err) => done(reject, err));
    client.on("close", () => {
      if (!data) done(reject, new Error("connection closed"));
    });
    client.setTimeout(15000, () => {
      client.destroy();
      done(reject, new Error("timeout"));
    });
  });
}

// ── Express + socket.io ──

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: "*" },
});

// ── REST API ──

app.get("/api/stats", async (req, res) => {
  try {
    const stats = await computeStats();
    res.json(stats);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/workspaces", async (req, res) => {
  try {
    const resp = await cmuxRpc("workspace.list");
    if (resp.ok && resp.result) {
      res.json(resp.result.workspaces || []);
    } else {
      res.json([]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/surfaces", async (req, res) => {
  try {
    const wsRef = req.query.workspace;
    const params = wsRef ? { workspace_id: wsRef } : {};
    const resp = await cmuxRpc("surface.list", params);
    if (resp.ok && resp.result) {
      res.json(resp.result);
    } else {
      res.json({ surfaces: [] });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/identify", async (req, res) => {
  try {
    const resp = await cmuxRpc("system.identify");
    if (resp.ok && resp.result) {
      res.json(resp.result);
    } else {
      res.json({});
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/terminal/:surfaceId", async (req, res) => {
  try {
    const surfaceId = req.params.surfaceId;
    const scrollback = req.query.scrollback === "true";
    const lines = parseInt(req.query.lines) || undefined;
    const params = { surface_id: surfaceId, scrollback };
    if (lines) params.lines = lines;
    const resp = await cmuxRpc("surface.read_text", params);
    if (resp.ok && resp.result) {
      res.json({ text: resp.result.text || "" });
    } else {
      res.json({ text: "" });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/traffic", async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const entries = await getRecentTraffic(limit);
    res.json(entries);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── 통계 계산 ──

async function computeStats() {
  const [reqLen, resLen] = await Promise.all([
    redis.xlen(STREAM_REQ),
    redis.xlen(STREAM_RES),
  ]);

  const now = Date.now();
  const oneMinAgo = `${now - 60000}-0`;

  const [reqEntries, resEntries] = await Promise.all([
    redis.xrange(STREAM_REQ, oneMinAgo, "+"),
    redis.xrange(STREAM_RES, oneMinAgo, "+"),
  ]);

  const methodCounts = {};
  let errorCount = 0;
  const pendingReqs = {};
  const latencies = [];

  for (const [, fields] of reqEntries) {
    const f = parseFields(fields);
    methodCounts[f.method] = (methodCounts[f.method] || 0) + 1;
    if (f.req_id) {
      pendingReqs[`${f.conn_id}:${f.req_id}`] = parseFloat(f.ts);
    }
  }

  for (const [, fields] of resEntries) {
    const f = parseFields(fields);
    if (f.ok === "false") errorCount++;
    if (f.req_id) {
      const key = `${f.conn_id}:${f.req_id}`;
      if (pendingReqs[key]) {
        latencies.push(parseFloat(f.ts) - pendingReqs[key]);
        delete pendingReqs[key];
      }
    }
  }

  const avgLatency =
    latencies.length > 0
      ? latencies.reduce((a, b) => a + b, 0) / latencies.length
      : 0;

  const sortedLat = [...latencies].sort((a, b) => a - b);
  const p99 =
    sortedLat.length > 0
      ? sortedLat[Math.floor(sortedLat.length * 0.99)]
      : 0;

  const sortedMethods = Object.entries(methodCounts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 15);

  return {
    requests: reqLen,
    responses: resLen,
    recentRequests: reqEntries.length,
    recentResponses: resEntries.length,
    avgLatency: Math.round(avgLatency * 10) / 10,
    p99Latency: Math.round(p99 * 10) / 10,
    errorRate:
      resEntries.length > 0
        ? Math.round((errorCount / resEntries.length) * 1000) / 10
        : 0,
    errorCount,
    methodCounts: Object.fromEntries(sortedMethods),
  };
}

// ── 최근 트래픽 ──

async function getRecentTraffic(limit) {
  const [reqEntries, resEntries] = await Promise.all([
    redis.xrevrange(STREAM_REQ, "+", "-", "COUNT", limit),
    redis.xrevrange(STREAM_RES, "+", "-", "COUNT", limit),
  ]);

  const entries = [];

  for (const [streamId, fields] of reqEntries) {
    entries.push({ streamId, stream: "requests", ...parseFields(fields) });
  }
  for (const [streamId, fields] of resEntries) {
    entries.push({ streamId, stream: "responses", ...parseFields(fields) });
  }

  entries.sort((a, b) => parseFloat(a.ts) - parseFloat(b.ts));
  return entries.slice(-limit);
}

// ── Redis 필드 파싱 ──

function parseFields(fields) {
  const result = {};
  for (let i = 0; i < fields.length; i += 2) {
    result[fields[i]] = fields[i + 1];
  }
  return result;
}

// ── 실시간 XREAD 루프 ──

let lastReqId = "$";
let lastResId = "$";
let lastTermId = "$";

async function streamLoop() {
  while (true) {
    try {
      const results = await redisSub.xread(
        "BLOCK",
        1000,
        "COUNT",
        100,
        "STREAMS",
        STREAM_REQ,
        STREAM_RES,
        STREAM_TERMINAL,
        lastReqId,
        lastResId,
        lastTermId
      );

      if (!results) continue;

      for (const [streamKey, entries] of results) {
        for (const [entryId, fields] of entries) {
          const parsed = parseFields(fields);

          if (streamKey === STREAM_TERMINAL) {
            io.emit("terminal", { streamId: entryId, ...parsed });
            lastTermId = entryId;
          } else {
            const stream =
              streamKey === STREAM_REQ ? "requests" : "responses";
            io.emit("traffic", { streamId: entryId, stream, ...parsed });
            if (streamKey === STREAM_REQ) lastReqId = entryId;
            else lastResId = entryId;
          }
        }
      }
    } catch (err) {
      if (err.message === "Connection is closed.") {
        console.error("[stream] Redis 연결 끊김, 1초 후 재시도...");
        await new Promise((r) => setTimeout(r, 1000));
      } else {
        console.error("[stream] XREAD 오류:", err.message);
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
  }
}

// ── 주기적 통계 푸시 ──

async function statsLoop() {
  while (true) {
    await new Promise((r) => setTimeout(r, 5000));
    try {
      const stats = await computeStats();
      io.emit("stats", stats);
    } catch (err) {
      console.error("[stats] 통계 계산 오류:", err.message);
    }
  }
}

// ── socket.io 연결 처리 ──

io.on("connection", async (socket) => {
  console.log(`[ws] 클라이언트 연결: ${socket.id}`);

  // 초기 데이터 전송
  try {
    const [stats, traffic, surfResp] = await Promise.all([
      computeStats(),
      getRecentTraffic(100),
      cmuxRpc("surface.list").catch(() => ({ ok: false })),
    ]);
    const surfaces = surfResp.ok ? surfResp.result?.surfaces || [] : [];
    socket.emit("init", { stats, traffic, surfaces });
  } catch (err) {
    console.error("[ws] 초기 데이터 전송 실패:", err.message);
  }

  socket.on("disconnect", () => {
    console.log(`[ws] 클라이언트 연결 해제: ${socket.id}`);
  });
});

// ── 서버 시작 ──

process.on("uncaughtException", (err) => {
  console.error("[server] uncaughtException:", err.message);
});
process.on("unhandledRejection", (err) => {
  console.error("[server] unhandledRejection:", err?.message || err);
});

httpServer.listen(PORT, () => {
  console.log(`[server] cmux Monitor 서버 시작: http://localhost:${PORT}`);
  console.log(`[server] Redis: ${REDIS_URL}`);

  streamLoop().catch((err) => console.error("[stream] 치명적 오류:", err));
  statsLoop().catch((err) => console.error("[stats] 치명적 오류:", err));
});
