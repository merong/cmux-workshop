import React from "react";
import { formatTime } from "../../utils/format";
import { pickNotify } from "../../utils/messagePresentation";

function getAlertClass(notifyType) {
  const lower = notifyType.toLowerCase();
  if (lower.includes("permission")) return "alert-permission";
  if (lower.includes("error")) return "alert-error";
  if (lower.includes("completed") || lower.includes("done")) return "alert-completed";
  if (lower.includes("waiting") || lower.includes("idle")) return "alert-waiting";
  return "alert-attention";
}

export default function AlertBadge({ msg, agent }) {
  const { type: notifyType, message: notifyMessage } = pickNotify(msg);
  const typeClass = getAlertClass(notifyType);

  return (
    <div className={`msg-alert ${typeClass}`} style={{ "--agent-color": agent.color }}>
      <div className="msg-alert__head">
        <span className="alert-type">{notifyType}</span>
        <span className="msg-alert__meta">
          <span className="alert-agent">{agent.label}</span>
          <span className="alert-time">{formatTime(msg.timestamp)}</span>
        </span>
      </div>
      <div className="msg-alert__body">{notifyMessage}</div>
    </div>
  );
}
