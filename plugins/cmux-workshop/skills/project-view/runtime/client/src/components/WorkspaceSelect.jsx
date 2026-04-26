import React, { useEffect, useState } from "react";
import { formatTime } from "../utils/format";

function WorkspaceCard({ workspace, onClick }) {
  return (
    <div className="workspace-card" onClick={() => onClick(workspace.workspace_id)}>
      <div className="ws-id">{workspace.workspace_id}</div>
      <div className="ws-cwd">{workspace.cwd || "\u2014"}</div>
      <div className="ws-meta">
        <span>{workspace.surface_ids.length} agent(s)</span>
        <span>{formatTime(workspace.last_activity)}</span>
      </div>
    </div>
  );
}

export default function WorkspaceSelect({ onSelect }) {
  const [workspaces, setWorkspaces] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch("/api/workspaces")
      .then((r) => r.json())
      .then((data) => {
        setWorkspaces(data);
        setLoading(false);
      })
      .catch((err) => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  return (
    <div className="screen">
      <header className="top-bar">
        <h1>Redis Chat UI</h1>
        <p className="subtitle">Select a workspace to view agent activity</p>
      </header>
      <div className="workspace-grid">
        {loading && (
          <p className="workspace-status">Loading...</p>
        )}
        {error && (
          <p className="workspace-status error">Failed to load workspaces: {error}</p>
        )}
        {!loading && !error && workspaces.length === 0 && (
          <p className="workspace-status">No workspaces found in stream.</p>
        )}
        {workspaces.map((ws) => (
          <WorkspaceCard key={ws.workspace_id} workspace={ws} onClick={onSelect} />
        ))}
      </div>
    </div>
  );
}
