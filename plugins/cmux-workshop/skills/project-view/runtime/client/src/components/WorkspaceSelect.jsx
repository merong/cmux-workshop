import React, { useEffect, useState } from "react";
import { formatTime } from "../utils/format";

function basenameFromPath(pathValue) {
  if (!pathValue) return "";
  const parts = pathValue.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] || pathValue;
}

function formatPorts(ports) {
  if (!Array.isArray(ports) || ports.length === 0) return "";
  const visible = ports.slice(0, 4).join(", ");
  return ports.length > 4 ? `${visible} +${ports.length - 4}` : visible;
}

function WorkspaceCard({ workspace, onClick }) {
  const projectInfo = workspace.project_info || {};
  const title =
    workspace.title ||
    projectInfo.project_name ||
    basenameFromPath(workspace.cwd) ||
    "Workspace";
  const summary = projectInfo.project_summary || workspace.description || "";
  const surfaceCount = workspace.cmux_surfaces?.length || workspace.surface_ids.length;
  const ports = formatPorts(workspace.listening_ports);
  const progress =
    projectInfo.total_phase_count > 0
      ? `${projectInfo.completed_phase_count}/${projectInfo.total_phase_count}`
      : "";

  return (
    <button
      type="button"
      className={`workspace-card${workspace.selected ? " is-selected" : ""}`}
      onClick={() => onClick(workspace.workspace_id)}
    >
      <div className="ws-card-head">
        <div className="ws-title-group">
          <span className="ws-title">{title}</span>
          <span className="ws-cwd">{workspace.cwd || "\u2014"}</span>
        </div>
        <div className="ws-badges">
          {workspace.selected && <span className="ws-badge selected">selected</span>}
          {workspace.ref && <span className="ws-badge">{workspace.ref}</span>}
        </div>
      </div>

      {summary && <p className="ws-summary">{summary}</p>}

      <div className="ws-detail-grid" aria-label="Workspace metadata">
        <span>
          <strong>{workspace.surface_ids.length}</strong>
          stream agent(s)
        </span>
        <span>
          <strong>{surfaceCount}</strong>
          surface(s)
        </span>
        {progress && (
          <span>
            <strong>{progress}</strong>
            phases
          </span>
        )}
        {projectInfo.git_branch && (
          <span>
            <strong>{projectInfo.git_branch}</strong>
            branch
          </span>
        )}
        {ports && (
          <span>
            <strong>{ports}</strong>
            ports
          </span>
        )}
      </div>

      <div className="ws-meta">
        <span className="ws-id">{workspace.workspace_id}</span>
        <span>{formatTime(workspace.last_activity)}</span>
      </div>
    </button>
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
        <h1>CMUX Workshop</h1>
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
