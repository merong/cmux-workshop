import { useRef, useEffect, useState } from "react";

function formatTs(ts) {
  if (!ts) return "";
  const d = new Date(parseInt(ts));
  return d.toLocaleTimeString("ko-KR", { hour12: false }) +
    "." + String(d.getMilliseconds()).padStart(3, "0");
}

function formatSize(size) {
  const n = parseInt(size);
  if (isNaN(n)) return size;
  if (n < 1024) return `${n}B`;
  return `${(n / 1024).toFixed(1)}KB`;
}

function TrafficEntry({ entry, onClick }) {
  const isReq = entry.direction === "request";
  const isError = !isReq && entry.ok === "false";

  const cls = isReq ? "entry-req" : isError ? "entry-err" : "entry-res";
  const arrow = isReq ? "→ REQ" : isError ? "← RES ✗" : "← RES ✓";
  const connShort = (entry.conn_id || "").slice(0, 8);

  return (
    <div className={`traffic-entry ${cls}`} onClick={() => onClick?.(entry)}>
      <span className="entry-ts">{formatTs(entry.ts)}</span>
      <span className="entry-arrow">{arrow}</span>
      <span className="entry-conn">[{connShort}]</span>
      <span className="entry-method">{entry.method || ""}</span>
      <span className="entry-size">({formatSize(entry.size)})</span>
    </div>
  );
}

export default function TrafficLog({ traffic, onClear, filter }) {
  const listRef = useRef(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [methodFilter, setMethodFilter] = useState(filter || "");
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    if (autoScroll && listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [traffic, autoScroll]);

  function handleScroll(e) {
    const el = e.target;
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 50;
    setAutoScroll(atBottom);
  }

  const filtered = methodFilter
    ? traffic.filter((e) =>
        (e.method || "").toLowerCase().includes(methodFilter.toLowerCase())
      )
    : traffic;

  return (
    <div className="traffic-view">
      <div className="traffic-toolbar">
        <h2>Traffic Log</h2>
        <input
          className="filter-input"
          placeholder="Filter by method..."
          value={methodFilter}
          onChange={(e) => setMethodFilter(e.target.value)}
        />
        {onClear && (
          <button className="btn-clear" onClick={onClear}>
            Clear
          </button>
        )}
      </div>

      <div className="traffic-list" ref={listRef} onScroll={handleScroll}>
        {filtered.length === 0 ? (
          <div className="dim" style={{ padding: "20px", textAlign: "center" }}>
            Waiting for traffic...
          </div>
        ) : (
          filtered.map((entry, i) => (
            <TrafficEntry
              key={entry.streamId || i}
              entry={entry}
              onClick={setSelected}
            />
          ))
        )}
      </div>

      {selected && (
        <div className="detail-panel">
          <div className="detail-header">
            <span>Detail — {selected.method}</span>
            <button onClick={() => setSelected(null)}>✕</button>
          </div>
          <pre className="detail-body">
            {(() => {
              try {
                return JSON.stringify(JSON.parse(selected.data), null, 2);
              } catch {
                return selected.data;
              }
            })()}
          </pre>
        </div>
      )}
    </div>
  );
}
