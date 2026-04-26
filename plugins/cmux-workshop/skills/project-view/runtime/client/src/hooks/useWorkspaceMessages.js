import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useWebSocket } from "./useWebSocket";
import { useWorkspaceHistory } from "./useWorkspaceHistory";

export function useWorkspaceMessages(workspaceId) {
  const { history, loading, error } = useWorkspaceHistory(workspaceId);
  const [liveState, setLiveState] = useState({ workspaceId, messages: [] });
  const workspaceIdRef = useRef(workspaceId);

  workspaceIdRef.current = workspaceId;

  useEffect(() => {
    setLiveState({ workspaceId, messages: [] });
  }, [workspaceId]);

  const onMessage = useCallback((msg) => {
    if (msg.workspace_id && msg.workspace_id !== workspaceIdRef.current) {
      return;
    }

    setLiveState((prev) => ({
      workspaceId: prev.workspaceId,
      messages: [...prev.messages, msg],
    }));
  }, []);

  const { status } = useWebSocket(workspaceId, onMessage);
  const liveMessages = liveState.workspaceId === workspaceId ? liveState.messages : [];

  const messages = useMemo(() => {
    const merged = [];
    const seenIds = new Set();

    for (const msg of history) {
      merged.push(msg);
      if (msg.id) seenIds.add(msg.id);
    }

    for (const msg of liveMessages) {
      if (msg.id && seenIds.has(msg.id)) continue;
      merged.push(msg);
      if (msg.id) seenIds.add(msg.id);
    }

    return merged;
  }, [history, liveMessages]);

  return {
    messages,
    status,
    historyLoading: loading,
    historyError: error,
  };
}
