import React from "react";
import { formatTime } from "../../utils/format";
import { pickSystemInfo } from "../../utils/messagePresentation";

export default function SystemBadge({ msg, agent }) {
  const isStart = msg.subcommand === "session-start" || msg.subcommand === "active";
  const isEnd = msg.subcommand === "session-end";
  const type = isStart ? "start" : isEnd ? "end" : "";
  const { model, source, endReason } = pickSystemInfo(msg);
  let title;
  let meta = [];
  if (isStart) {
    title = "Session started";
    meta = [agent.label, source, model].filter(Boolean);
  } else if (isEnd) {
    title = "Session ended";
    meta = [agent.label, endReason].filter(Boolean);
  } else {
    title = "System event";
    meta = [agent.label, msg.subcommand].filter(Boolean);
  }

  return (
    <div className={`msg-system ${type}`}>
      <span className="msg-system__time">{formatTime(msg.timestamp)}</span>
      <span className="msg-system__title">{title}</span>
      {meta.length > 0 && (
        <span className="msg-system__meta">{meta.join(" • ")}</span>
      )}
    </div>
  );
}
