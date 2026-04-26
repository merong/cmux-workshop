import React from "react";

export default function TopBar({ cwd, hostname, status, onBack, expandAll, onToggleExpandAll }) {
  const normalizedStatus = ["connected", "connecting", "disconnected"].includes(status)
    ? status
    : "connecting";

  return (
    <header className="top-bar">
      <div className="top-bar__primary">
        <button className="back-btn" onClick={onBack}>
          &larr; Back
        </button>
        <div className="workspace-info">
          <span className="header-cwd">{cwd}</span>
          {hostname && (
            <span className="header-hostname">{hostname}</span>
          )}
        </div>
      </div>
      <div className="top-bar__secondary">
        <div
          className={`connection-status status-pill status-pill--${normalizedStatus}`}
          aria-label={`Connection status: ${normalizedStatus}`}
        >
          <span className="status-pill__dot" aria-hidden="true" />
          <span className="status-pill__label">{normalizedStatus}</span>
        </div>
        <button
          className={`expand-all-btn${expandAll ? " active" : ""}`}
          onClick={onToggleExpandAll}
          title={expandAll ? "Collapse all details" : "Expand all details"}
          aria-pressed={expandAll}
          aria-label="Toggle all detail panels"
        >
          {expandAll ? "\u25BC All" : "\u25B6 All"}
        </button>
      </div>
    </header>
  );
}
