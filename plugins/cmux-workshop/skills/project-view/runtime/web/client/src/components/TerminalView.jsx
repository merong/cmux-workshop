import { useEffect, useState } from "react";

export default function TerminalView({ surface, terminalScreens }) {
  const sid = surface?.ref || "";
  const lines = terminalScreens[sid] || [];
  const [liveText, setLiveText] = useState(null);

  // 초기 로드: API에서 현재 화면 가져오기
  useEffect(() => {
    if (!sid) return;
    fetch(`/api/terminal/${encodeURIComponent(sid)}`)
      .then((r) => r.json())
      .then((data) => {
        if (data.text) setLiveText(data.text);
      })
      .catch(() => {});
  }, [sid]);

  const displayLines =
    lines.length > 0 ? lines : liveText ? liveText.split("\n") : [];

  return (
    <div className="terminal-view">
      <div className="terminal-header">
        <h2>Terminal — {surface?.title || sid}</h2>
        <div className="terminal-meta">
          <span className="tag">{sid}</span>
          {surface?.type && <span className="tag">{surface.type}</span>}
        </div>
      </div>
      <div className="terminal-screen">
        {displayLines.length === 0 ? (
          <div className="dim" style={{ padding: 20, textAlign: "center" }}>
            Waiting for screen data...
            <br />
            <span style={{ fontSize: 11 }}>
              polling_monitor.py를 실행하면 화면이 표시됩니다
            </span>
          </div>
        ) : (
          displayLines.map((line, i) => (
            <div key={i} className="terminal-line">
              <span className="line-no">{i + 1}</span>
              <span className="line-text">{line || "\u00A0"}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
