import React, { useState, useEffect, useCallback } from "react";
import WorkspaceSelect from "./components/WorkspaceSelect";
import ChatView from "./components/ChatView";

function getWorkspaceIdFromUrl() {
  return new URLSearchParams(window.location.search).get("workspace_id");
}

export default function App() {
  const [workspaceId, setWorkspaceId] = useState(getWorkspaceIdFromUrl);

  const navigate = useCallback((id) => {
    if (id) {
      history.pushState(null, "", `?workspace_id=${id}`);
    } else {
      history.pushState(null, "", "/");
    }
    setWorkspaceId(id);
  }, []);

  useEffect(() => {
    const handler = () => setWorkspaceId(getWorkspaceIdFromUrl());
    window.addEventListener("popstate", handler);
    return () => window.removeEventListener("popstate", handler);
  }, []);

  if (workspaceId) {
    return <ChatView workspaceId={workspaceId} onBack={() => navigate(null)} />;
  }
  return <WorkspaceSelect onSelect={navigate} />;
}
