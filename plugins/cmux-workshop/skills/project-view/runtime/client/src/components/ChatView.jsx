import React, { useMemo, useState } from "react";
import TopBar from "./TopBar";
import AgentSidebar from "./AgentSidebar";
import Timeline from "./Timeline";
import { useAgents } from "../hooks/useAgents";
import { useAutoScroll } from "../hooks/useAutoScroll";
import { useWorkspaceMessages } from "../hooks/useWorkspaceMessages";
import { useWorkspaceSurfaces } from "../hooks/useWorkspaceSurfaces";

export default function ChatView({ workspaceId, onBack }) {
  const [expandAll, setExpandAll] = useState(false);
  const { messages, status } = useWorkspaceMessages(workspaceId);
  const surfacesById = useWorkspaceSurfaces(workspaceId);
  const { agents, agentsById } = useAgents(messages, surfacesById);
  const headerInfo = useMemo(() => {
    const lastMessage = messages[messages.length - 1];
    return {
      cwd: lastMessage?.cwd || "",
      hostname: lastMessage?.hostname || "",
    };
  }, [messages]);

  const { ref: timelineRef, atBottom, handleScroll, scrollToBottom } =
    useAutoScroll(messages.length);

  return (
    <div className="screen">
      <TopBar
        cwd={headerInfo.cwd}
        hostname={headerInfo.hostname}
        status={status}
        onBack={onBack}
        expandAll={expandAll}
        onToggleExpandAll={() => setExpandAll((v) => !v)}
      />
      <div className="chat-layout">
        <AgentSidebar agents={agents} />
        <Timeline
          messages={messages}
          agentsById={agentsById}
          timelineRef={timelineRef}
          onScroll={handleScroll}
          expandAll={expandAll}
        />
      </div>
      {!atBottom && (
        <button className="scroll-bottom-btn" onClick={scrollToBottom}>
          Latest &darr;
        </button>
      )}
    </div>
  );
}
