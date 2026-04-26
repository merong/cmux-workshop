export default function Sidebar({
  connected,
  stats,
  workspaces,
  surfaces,
  currentView,
  selectedWorkspace,
  selectedSurface,
  onNavigate,
  onSelectWorkspace,
  onSelectSurface,
}) {
  return (
    <aside className="sidebar">
      <div className="sidebar-logo">⚡ cmux Monitor</div>

      <div className="sidebar-section">
        <div className="sidebar-label">Overview</div>
        <div
          className={`sidebar-item ${currentView === "dashboard" ? "active" : ""}`}
          onClick={() => onNavigate("dashboard")}
        >
          📊 Dashboard
        </div>
        <div
          className={`sidebar-item ${currentView === "traffic" ? "active" : ""}`}
          onClick={() => onNavigate("traffic")}
        >
          📡 All Traffic
        </div>
      </div>

      <div className="sidebar-section">
        <div className="sidebar-label">Workspaces</div>
        {workspaces.length === 0 && (
          <div className="sidebar-item dim">No workspaces</div>
        )}
        {workspaces.map((ws) => (
          <div
            key={ws.ref || ws.id || ws.title}
            className={`sidebar-item ${
              currentView === "workspace" &&
              selectedWorkspace?.ref === ws.ref
                ? "active"
                : ""
            }`}
            onClick={() => onSelectWorkspace(ws)}
          >
            <span
              className={`status-dot ${ws.selected ? "active" : ""}`}
            />
            <span className="ws-title">{ws.title || ws.ref}</span>
          </div>
        ))}
      </div>

      {surfaces && surfaces.length > 0 && (
        <div className="sidebar-section">
          <div className="sidebar-label">Surfaces</div>
          {surfaces.map((s) => (
            <div
              key={s.ref || s.id}
              className={`sidebar-item ${
                currentView === "terminal" &&
                selectedSurface?.ref === s.ref
                  ? "active"
                  : ""
              }`}
              onClick={() => onSelectSurface(s)}
            >
              <span className={`status-dot ${s.focused ? "active" : ""}`} />
              <span className="ws-title">
                {s.title
                  ? s.title.length > 22
                    ? "…" + s.title.slice(-21)
                    : s.title
                  : s.ref}
              </span>
            </div>
          ))}
        </div>
      )}

      <div className="sidebar-footer">
        <div className={`conn-status ${connected ? "ok" : "err"}`}>
          ● {connected ? "Connected" : "Disconnected"}
        </div>
        {stats && (
          <div className="sidebar-stats">
            Redis: {stats.requests?.toLocaleString()} req /{" "}
            {stats.responses?.toLocaleString()} res
          </div>
        )}
      </div>
    </aside>
  );
}
