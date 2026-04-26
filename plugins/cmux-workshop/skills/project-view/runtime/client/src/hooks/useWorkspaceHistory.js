import { useEffect, useState } from "react";

export function useWorkspaceHistory(workspaceId) {
  const [state, setState] = useState({
    workspaceId,
    history: [],
    loading: Boolean(workspaceId),
    error: null,
  });

  useEffect(() => {
    if (!workspaceId) {
      setState({
        workspaceId,
        history: [],
        loading: false,
        error: null,
      });
      return undefined;
    }

    const controller = new AbortController();

    setState({
      workspaceId,
      history: [],
      loading: true,
      error: null,
    });

    fetch(`/api/history?workspace_id=${encodeURIComponent(workspaceId)}&count=200`, {
      signal: controller.signal,
    })
      .then((response) => response.json())
      .then((history) => {
        setState({
          workspaceId,
          history: Array.isArray(history) ? history : [],
          loading: false,
          error: null,
        });
      })
      .catch((error) => {
        if (error.name === "AbortError") return;

        setState({
          workspaceId,
          history: [],
          loading: false,
          error: error.message,
        });
      });

    return () => controller.abort();
  }, [workspaceId]);

  if (state.workspaceId !== workspaceId) {
    return { history: [], loading: Boolean(workspaceId), error: null };
  }

  return {
    history: state.history,
    loading: state.loading,
    error: state.error,
  };
}
