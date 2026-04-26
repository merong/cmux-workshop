import React from "react";

export default function ViewToggle({ mode, onToggle }) {
  return (
    <span className="view-toggle" role="group" aria-label="Message view mode">
      <button
        type="button"
        className={mode === "md" ? "active" : ""}
        aria-pressed={mode === "md"}
        onClick={() => onToggle("md")}
      >
        md
      </button>
      <button
        type="button"
        className={mode === "raw" ? "active" : ""}
        aria-pressed={mode === "raw"}
        onClick={() => onToggle("raw")}
      >
        raw
      </button>
    </span>
  );
}
