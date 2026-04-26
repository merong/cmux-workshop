import { useEffect, useRef, useState } from "react";

export function useWebSocket(workspaceId, onMessage) {
  const wsRef = useRef(null);
  const onMessageRef = useRef(onMessage);
  const [status, setStatus] = useState("connecting");

  onMessageRef.current = onMessage;

  useEffect(() => {
    if (!workspaceId) {
      setStatus("disconnected");
      return undefined;
    }

    let reconnectTimer;
    let cancelled = false;

    function connect() {
      if (cancelled) return;

      setStatus("connecting");
      const protocol = location.protocol === "https:" ? "wss:" : "ws:";
      const ws = new WebSocket(`${protocol}//${location.host}`);
      wsRef.current = ws;

      ws.addEventListener("open", () => {
        if (cancelled) return;
        setStatus("connected");
        ws.send(JSON.stringify({ type: "subscribe", workspace_id: workspaceId }));
      });

      ws.addEventListener("message", (event) => {
        try {
          const envelope = JSON.parse(event.data);
          if (envelope.type === "event") {
            onMessageRef.current?.(envelope.data);
          }
        } catch {
          // ignore
        }
      });

      ws.addEventListener("close", () => {
        if (cancelled) return;
        setStatus("disconnected");
        reconnectTimer = setTimeout(() => {
          connect();
        }, 3000);
      });

      ws.addEventListener("error", () => {
        if (cancelled) return;
        setStatus("disconnected");
      });
    }

    connect();

    return () => {
      cancelled = true;
      clearTimeout(reconnectTimer);
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [workspaceId]);

  return { status };
}
