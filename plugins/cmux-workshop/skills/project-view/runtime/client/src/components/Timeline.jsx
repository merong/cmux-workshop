import React from "react";
import { pickChatRole, pickDisplayStyle } from "../utils/messagePresentation";
import SystemBadge from "./messages/SystemBadge";
import UserBubble from "./messages/UserBubble";
import AiBubble from "./messages/AiBubble";
import ToolCompact from "./messages/ToolCompact";
import AlertBadge from "./messages/AlertBadge";

function MessageItem({ msg, agent, expandAll }) {
  const style = pickDisplayStyle(msg);
  const chatRole = pickChatRole(msg);

  switch (style) {
    case "bubble":
      if (chatRole === "user") {
        return <UserBubble msg={msg} agent={agent} expandAll={expandAll} />;
      }
      return <AiBubble msg={msg} agent={agent} expandAll={expandAll} />;
    case "compact":
      return <ToolCompact msg={msg} agent={agent} expandAll={expandAll} />;
    case "alert":
      return <AlertBadge msg={msg} agent={agent} />;
    case "badge":
    default:
      return <SystemBadge msg={msg} agent={agent} />;
  }
}

export default function Timeline({ messages, agentsById, timelineRef, onScroll, expandAll }) {
  return (
    <main className="timeline" ref={timelineRef} onScroll={onScroll}>
      {messages.map((msg, i) => {
        const agent = agentsById.get(msg.surface_id) || {
          id: msg.surface_id || "unknown",
          color: "#58a6ff",
          label: (msg.surface_id || "unknown").substring(0, 8),
        };

        return (
          <MessageItem
            key={msg.id || i}
            msg={msg}
            agent={agent}
            expandAll={expandAll}
          />
        );
      })}
    </main>
  );
}
