import React, { useEffect, useMemo, useState } from "react";
import TopBar from "./TopBar";
import AgentSidebar from "./AgentSidebar";
import Timeline from "./Timeline";
import { useAgents } from "../hooks/useAgents";
import { useAutoScroll } from "../hooks/useAutoScroll";
import { useWorkspaceMessages } from "../hooks/useWorkspaceMessages";
import { useWorkspaceSurfaces } from "../hooks/useWorkspaceSurfaces";

export default function ChatView({ workspaceId, onBack }) {
  const [expandAll, setExpandAll] = useState(false);
  const [selectedAgentId, setSelectedAgentId] = useState(null);
  const { messages, status } = useWorkspaceMessages(workspaceId);
  const surfacesById = useWorkspaceSurfaces(workspaceId);
  const { agents, agentsById } = useAgents(messages, surfacesById);
  const filteredMessages = useMemo(() => {
    if (!selectedAgentId) return messages;
    return messages.filter((msg) => msg.surface_id === selectedAgentId);
  }, [messages, selectedAgentId]);

  useEffect(() => {
    if (selectedAgentId && !agentsById.has(selectedAgentId)) {
      setSelectedAgentId(null);
    }
  }, [agentsById, selectedAgentId]);

  const headerInfo = useMemo(() => {
    const lastMessage = messages[messages.length - 1];
    return {
      cwd: lastMessage?.cwd || "",
      hostname: lastMessage?.hostname || "",
    };
  }, [messages]);

  const { ref: timelineRef, atBottom, handleScroll, scrollToBottom } =
    useAutoScroll(filteredMessages.length);

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
        <AgentSidebar
          agents={agents}
          totalMessages={messages.length}
          selectedAgentId={selectedAgentId}
          onSelectAgent={setSelectedAgentId}
        />
        <Timeline
          messages={filteredMessages}
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
