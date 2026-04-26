import { useEffect, useRef, useState } from "react";
import TrafficLog from "./TrafficLog.jsx";

export default function WorkspaceView({
  workspace,
  traffic,
  terminalScreens,
  onSelectSurface,
}) {
  const wsRef = workspace.ref || "";
  const [surfaceData, setSurfaceData] = useState(null);
  const [selected, setSelected] = useState(null); // { type, data }
  const [screenText, setScreenText] = useState("");

  useEffect(() => {
    setSurfaceData(null);
    setSelected(null);
    setScreenText("");
    fetch(`/api/surfaces?workspace=${encodeURIComponent(wsRef)}`)
      .then((r) => r.json())
      .then(setSurfaceData)
      .catch(() => setSurfaceData(null));
  }, [wsRef]);

  // surface 선택 시 화면 텍스트 로드
  const selectedSurfaceRef = selected?.type === "surface" ? selected.data.ref : null;

  useEffect(() => {
    if (!selectedSurfaceRef) {
      setScreenText("");
      return;
    }
    // 항상 API에서 최신 화면을 가져옴
    fetch(`/api/terminal/${encodeURIComponent(selectedSurfaceRef)}`)
      .then((r) => r.json())
      .then((d) => setScreenText(d.text || ""))
      .catch(() => setScreenText(""));
  }, [selectedSurfaceRef]);

  // pane별로 surface 그룹화
  const panes = {};
  const surfaces = surfaceData?.surfaces || [];
  for (const s of surfaces) {
    const paneRef = s.pane_ref || "unknown";
    if (!panes[paneRef]) {
      panes[paneRef] = { ref: paneRef, id: s.pane_id, surfaces: [] };
    }
    panes[paneRef].surfaces.push(s);
  }

  const windowId = surfaceData?.window_id || "";

  const wsTraffic = traffic.filter((e) => {
    const data = e.data || "";
    return data.includes(wsRef) || data.includes(workspace.title || "");
  });

  return (
    <div className="workspace-view">
      {/* Header */}
      <div className="workspace-header">
        <h2>{workspace.title || wsRef}</h2>
        <div className="workspace-meta">
          <span className="tag">{wsRef}</span>
          {workspace.selected && <span className="tag active">Selected</span>}
          {workspace.current_directory && (
            <span className="tag">{workspace.current_directory}</span>
          )}
          {workspace.custom_color && (
            <span
              className="tag"
              style={{
                borderColor: workspace.custom_color,
                color: workspace.custom_color,
              }}
            >
              {workspace.custom_color}
            </span>
          )}
        </div>
      </div>

      {/* Hierarchy */}
      <div className="hierarchy">
        {/* Window */}
        <div
          className={`hier-node hier-window ${selected?.type === "window" ? "selected" : ""}`}
          onClick={() =>
            setSelected({ type: "window", data: { id: windowId } })
          }
        >
          <span className="hier-icon">🪟</span>
          <span className="hier-label">Window</span>
          <span className="hier-ref">{windowId ? windowId.slice(0, 8) + "…" : "—"}</span>
        </div>

        {/* Panes */}
        <div className="hier-children">
          {Object.values(panes).map((pane) => (
            <div key={pane.ref} className="hier-group">
              <div
                className={`hier-node hier-pane ${selected?.type === "pane" && selected.data.ref === pane.ref ? "selected" : ""}`}
                onClick={() => setSelected({ type: "pane", data: pane })}
              >
                <span className="hier-icon">📐</span>
                <span className="hier-label">Pane</span>
                <span className="hier-ref">{pane.ref}</span>
                <span className="hier-count">
                  {pane.surfaces.length} surface{pane.surfaces.length > 1 ? "s" : ""}
                </span>
              </div>

              {/* Surfaces */}
              <div className="hier-children">
                {pane.surfaces.map((s) => (
                  <div
                    key={s.ref}
                    className={`hier-node hier-surface ${selected?.type === "surface" && selected.data.ref === s.ref ? "selected" : ""}`}
                    onClick={() => setSelected({ type: "surface", data: s })}
                  >
                    <span className="hier-icon">
                      {s.type === "browser" ? "🌐" : "💻"}
                    </span>
                    <span className="hier-label">
                      {s.title
                        ? s.title.length > 30
                          ? "…" + s.title.slice(-29)
                          : s.title
                        : s.ref}
                    </span>
                    <span className="hier-ref">{s.ref}</span>
                    {s.focused && <span className="hier-badge focus">focused</span>}
                    {s.selected_in_pane && (
                      <span className="hier-badge">selected</span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Detail Panel */}
      {selected && (
        <div className="detail-section">
          {selected.type === "window" && (
            <WindowDetail windowId={windowId} paneCount={Object.keys(panes).length} surfaceCount={surfaces.length} />
          )}
          {selected.type === "pane" && (
            <PaneDetail pane={selected.data} />
          )}
          {selected.type === "surface" && (
            <SurfaceDetail
              surface={selected.data}
              screenText={screenText}
              onOpenTerminal={onSelectSurface}
            />
          )}
        </div>
      )}

      {/* Traffic */}
      {wsTraffic.length > 0 && (
        <div className="panel" style={{ marginTop: 12 }}>
          <div className="panel-header">
            Workspace Traffic ({wsTraffic.length})
          </div>
          <TrafficLog traffic={wsTraffic} />
        </div>
      )}
    </div>
  );
}

function WindowDetail({ windowId, paneCount, surfaceCount }) {
  return (
    <div className="detail-card">
      <h3>🪟 Window</h3>
      <div className="detail-grid">
        <div className="detail-row">
          <span className="detail-key">ID</span>
          <span className="detail-val mono">{windowId || "—"}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Panes</span>
          <span className="detail-val">{paneCount}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Surfaces</span>
          <span className="detail-val">{surfaceCount}</span>
        </div>
      </div>
    </div>
  );
}

function PaneDetail({ pane }) {
  return (
    <div className="detail-card">
      <h3>📐 Pane</h3>
      <div className="detail-grid">
        <div className="detail-row">
          <span className="detail-key">Ref</span>
          <span className="detail-val mono">{pane.ref}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">ID</span>
          <span className="detail-val mono">{pane.id || "—"}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Surfaces</span>
          <span className="detail-val">{pane.surfaces.length}</span>
        </div>
      </div>
      <div className="detail-sub">
        <div className="detail-sub-title">Surfaces in this pane:</div>
        {pane.surfaces.map((s) => (
          <div key={s.ref} className="detail-sub-item">
            <span className="mono">{s.ref}</span> — {s.title || "(untitled)"}
            {s.focused && <span className="hier-badge focus">focused</span>}
          </div>
        ))}
      </div>
    </div>
  );
}

function SurfaceDetail({ surface, screenText, onOpenTerminal }) {
  const s = surface;
  const screenRef = useRef(null);
  const fullScreenRef = useRef(null);
  const [fullText, setFullText] = useState(null);
  const [loadingFull, setLoadingFull] = useState(false);

  useEffect(() => {
    if (screenRef.current) {
      screenRef.current.scrollTo({ top: screenRef.current.scrollHeight, behavior: "smooth" });
    }
  }, [screenText]);

  useEffect(() => {
    setFullText(null);
  }, [s.ref]);

  useEffect(() => {
    if (fullText && fullScreenRef.current) {
      fullScreenRef.current.scrollTo({ top: fullScreenRef.current.scrollHeight, behavior: "smooth" });
    }
  }, [fullText]);

  function handleExpand() {
    setLoadingFull(true);
    fetch(`/api/terminal/${encodeURIComponent(s.ref)}?scrollback=true`)
      .then((r) => r.json())
      .then((d) => setFullText(d.text || ""))
      .catch(() => setFullText("Failed to load"))
      .finally(() => setLoadingFull(false));
  }

  return (
    <div className="detail-card">
      <div className="detail-card-header">
        <h3>{s.type === "browser" ? "🌐" : "💻"} Surface</h3>
        {s.type === "terminal" && onOpenTerminal && (
          <button
            className="btn-terminal"
            onClick={() => onOpenTerminal(s)}
          >
            Open Terminal View →
          </button>
        )}
      </div>
      <div className="detail-grid">
        <div className="detail-row">
          <span className="detail-key">Ref</span>
          <span className="detail-val mono">{s.ref}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">ID</span>
          <span className="detail-val mono">{s.id}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Title</span>
          <span className="detail-val">{s.title || "—"}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Type</span>
          <span className="detail-val">{s.type}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Pane</span>
          <span className="detail-val mono">{s.pane_ref}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Index</span>
          <span className="detail-val">{s.index}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Focused</span>
          <span className="detail-val">{s.focused ? "Yes" : "No"}</span>
        </div>
        <div className="detail-row">
          <span className="detail-key">Selected in Pane</span>
          <span className="detail-val">{s.selected_in_pane ? "Yes" : "No"}</span>
        </div>
      </div>

      {screenText && (
        <div className="detail-screen-preview">
          <div className="detail-sub-title">
            Screen Preview
            <button
              className="btn-expand"
              onClick={handleExpand}
              disabled={loadingFull}
              title="전체 스크롤백 보기"
            >
              {loadingFull ? "⏳" : "⛶"}
            </button>
          </div>
          <div className="terminal-screen compact" ref={screenRef}>
            {screenText.split("\n").map((line, i) => (
              <div key={i} className="terminal-line">
                <span className="line-text">{line || "\u00A0"}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {fullText !== null && (
        <div className="fullscreen-modal" onClick={() => setFullText(null)}>
          <div className="fullscreen-content" onClick={(e) => e.stopPropagation()}>
            <div className="fullscreen-header">
              <span>
                {s.title || s.ref} — Full Scrollback ({fullText.split("\n").length} lines)
              </span>
              <button onClick={() => setFullText(null)}>✕</button>
            </div>
            <div className="terminal-screen fullscreen-terminal" ref={fullScreenRef}>
              {fullText.split("\n").map((line, i) => (
                <div key={i} className="terminal-line">
                  <span className="line-no">{i + 1}</span>
                  <span className="line-text">{line || "\u00A0"}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
