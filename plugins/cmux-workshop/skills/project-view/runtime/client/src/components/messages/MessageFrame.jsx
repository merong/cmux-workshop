import React, { useId, useState } from "react";
import { formatTime } from "../../utils/format";
import DetailPanel from "./DetailPanel";
import ViewToggle from "./ViewToggle";

export default function MessageFrame({
  msg,
  agent,
  expandAll,
  wrapperClassName,
  containerClassName,
  borderWidth,
  agentLabel,
  showViewToggle = false,
  renderHeader,
  renderBody,
  renderMetaExtra,
  renderInlineContent,
}) {
  const [viewMode, setViewMode] = useState("md");
  const [detailOverride, setDetailOverride] = useState(null);
  const reactId = useId();

  const hasDetail = Boolean(msg.detail_ref && msg.detail_hash);
  const detailVisible = hasDetail && (detailOverride ?? expandAll);
  const detailPanelId = hasDetail ? `detail-panel-${reactId.replace(/:/g, "")}` : undefined;
  const toggleDetail = () => {
    setDetailOverride((value) => !(value ?? expandAll));
  };
  const closeDetail = () => {
    setDetailOverride(false);
  };
  const timeText = formatTime(msg.timestamp);
  const containerStyle = {
    "--agent-color": agent.color,
    "--agent-border-width": borderWidth ? `${borderWidth}px` : undefined,
  };
  const header = renderHeader
    ? renderHeader({ agent })
    : agentLabel
      ? (
          <div className="agent-label">
            <span className="agent-label__text">{agentLabel}</span>
          </div>
        )
      : null;

  return (
    <div className={wrapperClassName}>
      <div className={containerClassName} style={containerStyle}>
        {renderInlineContent ? (
          renderInlineContent({
            hasDetail,
            detailVisible,
            toggleDetail,
            timeText,
            viewMode,
            setViewMode,
            detailPanelId,
          })
        ) : (
          <>
            {header}
            {renderBody({ viewMode, setViewMode })}
            <div className="msg-meta">
              <span className="msg-meta__time">{timeText}</span>
              <span className="msg-meta__controls">
                {showViewToggle && (
                  <ViewToggle mode={viewMode} onToggle={setViewMode} />
                )}
                {hasDetail && (
                  <button
                    className="detail-btn"
                    type="button"
                    aria-expanded={detailVisible}
                    aria-controls={detailPanelId}
                    aria-label={detailVisible ? "Hide detail" : "Show detail"}
                    onClick={toggleDetail}
                  >
                    detail
                  </button>
                )}
                {renderMetaExtra?.({
                  hasDetail,
                  detailVisible,
                  toggleDetail,
                  timeText,
                  viewMode,
                  setViewMode,
                  detailPanelId,
                })}
              </span>
            </div>
          </>
        )}
      </div>
      {hasDetail && (
        <DetailPanel
          panelId={detailPanelId}
          detailHash={msg.detail_hash}
          detailRef={msg.detail_ref}
          isOpen={detailVisible}
          onClose={closeDetail}
        />
      )}
    </div>
  );
}
