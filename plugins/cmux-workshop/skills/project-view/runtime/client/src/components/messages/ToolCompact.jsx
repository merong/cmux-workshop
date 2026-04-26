import React from "react";
import {
  pickToolName,
  pickToolSummary,
  pickToolInputView,
} from "../../utils/messagePresentation";
import MessageFrame from "./MessageFrame";

export default function ToolCompact({ msg, agent, expandAll }) {
  const toolName = pickToolName(msg) || "unknown";
  const { primary, secondary, code } = pickToolInputView(msg);
  const hasView = primary || secondary || code;
  const summaryFallback = !hasView ? pickToolSummary(msg) : "";

  return (
    <MessageFrame
      msg={msg}
      agent={agent}
      expandAll={expandAll}
      wrapperClassName="msg-tool-wrapper"
      containerClassName="msg-tool"
      borderWidth={2}
      renderInlineContent={({ hasDetail, detailVisible, toggleDetail, timeText, detailPanelId }) => (
        <div className="msg-tool__row">
          <div className="msg-tool__primary">
            <div className="msg-tool__head">
              <span className="tool-name">{toolName}</span>
              {primary && <span className="msg-tool__description">{primary}</span>}
              {secondary && <span className="msg-tool__meta">{secondary}</span>}
              {summaryFallback && <span className="msg-tool__summary">{summaryFallback}</span>}
            </div>
            {code && <code className="msg-tool__command">{code}</code>}
          </div>
          <div className="msg-tool__secondary">
            <span className="tool-time">{timeText}</span>
            {hasDetail && (
              <button
                className="tool-expand-btn"
                type="button"
                aria-expanded={detailVisible}
                aria-controls={detailPanelId}
                aria-label={detailVisible ? "Hide detail" : "Show detail"}
                onClick={toggleDetail}
              >
                {detailVisible ? "\u25BC" : "\u25B6"}
              </button>
            )}
          </div>
        </div>
      )}
    />
  );
}
