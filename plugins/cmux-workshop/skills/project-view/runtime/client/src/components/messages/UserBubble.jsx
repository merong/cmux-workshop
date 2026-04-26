import React from "react";
import { pickPrompt } from "../../utils/messagePresentation";
import MsgText from "./MsgText";
import MessageFrame from "./MessageFrame";

export default function UserBubble({ msg, agent, expandAll }) {
  const prompt = pickPrompt(msg) || "(empty)";

  return (
    <MessageFrame
      msg={msg}
      agent={agent}
      expandAll={expandAll}
      wrapperClassName="msg-bubble-wrapper msg-user-wrapper"
      containerClassName="msg-bubble msg-user"
      borderWidth={3}
      renderHeader={() => (
        <div className="agent-label agent-label--user">
          <span className="agent-label__text">{agent.label}</span>
        </div>
      )}
      showViewToggle
      renderBody={({ viewMode }) => (
        <div className="msg-bubble__body msg-bubble__body--user">
          <MsgText text={prompt} mode={viewMode} />
        </div>
      )}
    />
  );
}
