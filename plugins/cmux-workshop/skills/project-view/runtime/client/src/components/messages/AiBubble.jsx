import React from "react";
import { pickResponse, pickStopReason } from "../../utils/messagePresentation";
import MsgText from "./MsgText";
import MessageFrame from "./MessageFrame";

export default function AiBubble({ msg, agent, expandAll }) {
  const raw = pickResponse(msg) || "(no response)";
  const text = raw.length > 5000 ? raw.substring(0, 5000) + "\n\n...(truncated)" : raw;
  const stopReason = pickStopReason(msg);

  return (
    <MessageFrame
      msg={msg}
      agent={agent}
      expandAll={expandAll}
      wrapperClassName="msg-bubble-wrapper msg-ai-wrapper"
      containerClassName="msg-bubble msg-ai"
      borderWidth={3}
      renderHeader={() => (
        <div className="agent-label agent-label--ai">
          <span className="agent-label__dot" aria-hidden="true" />
          <span className="agent-label__text">{agent.label}</span>
          <span className="agent-label__role">AI</span>
        </div>
      )}
      showViewToggle
      renderBody={({ viewMode }) => (
        <div className="msg-bubble__body msg-bubble__body--ai">
          <MsgText text={text} mode={viewMode} />
        </div>
      )}
      renderMetaExtra={() => (
        stopReason ? <span className="stop-reason">{stopReason}</span> : null
      )}
    />
  );
}
