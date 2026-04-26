import { useEffect, useRef, useState, useCallback } from "react";
import { io } from "socket.io-client";

const MAX_ENTRIES = 500;

export function useSocket() {
  const socketRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [stats, setStats] = useState(null);
  const [traffic, setTraffic] = useState([]);
  const [surfaces, setSurfaces] = useState([]);
  const [terminalScreens, setTerminalScreens] = useState({});

  useEffect(() => {
    const socket = io({ transports: ["websocket"] });
    socketRef.current = socket;

    socket.on("connect", () => setConnected(true));
    socket.on("disconnect", () => setConnected(false));

    socket.on("init", (data) => {
      setStats(data.stats);
      setTraffic(data.traffic);
      if (data.surfaces) setSurfaces(data.surfaces);
    });

    socket.on("stats", (data) => {
      setStats(data);
    });

    socket.on("traffic", (entry) => {
      setTraffic((prev) => {
        const next = [...prev, entry];
        return next.length > MAX_ENTRIES ? next.slice(-MAX_ENTRIES) : next;
      });
    });

    socket.on("terminal", (entry) => {
      const sid = entry.surface_id;
      if (!sid) return;

      if (entry.event === "screen_snapshot" && entry.full_text) {
        setTerminalScreens((prev) => ({
          ...prev,
          [sid]: entry.full_text.split("\n"),
        }));
      } else if (entry.event === "screen_changed" && entry.diff) {
        try {
          const diff = JSON.parse(entry.diff);
          setTerminalScreens((prev) => {
            const lines = [...(prev[sid] || [])];
            for (const [lineNo, text] of Object.entries(diff)) {
              const idx = parseInt(lineNo);
              while (lines.length <= idx) lines.push("");
              lines[idx] = text;
            }
            return { ...prev, [sid]: lines };
          });
        } catch {
          // ignore parse errors
        }
      }
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  const clearTraffic = useCallback(() => setTraffic([]), []);

  return {
    connected,
    stats,
    traffic,
    clearTraffic,
    surfaces,
    terminalScreens,
  };
}
