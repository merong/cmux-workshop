import React, { useState } from "react";

export default function AgentSidebar({
  agents,
  totalMessages,
  selectedAgentId,
  onSelectAgent,
}) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <aside className={`agent-sidebar${collapsed ? " is-collapsed" : ""}`}>
      <div className="agent-sidebar__header">
        <h3>Agents</h3>
        <button
          type="button"
          className="agent-sidebar__toggle"
          aria-label={collapsed ? "Expand agent sidebar" : "Collapse agent sidebar"}
          aria-pressed={collapsed}
          onClick={() => setCollapsed((value) => !value)}
          title={collapsed ? "Expand agents" : "Collapse agents"}
        >
          {collapsed ? ">" : "<"}
        </button>
      </div>
      <ul className="agent-list">
        <li>
          <button
            type="button"
            className={`agent-card agent-card--all${selectedAgentId === null ? " is-active" : ""}`}
            aria-pressed={selectedAgentId === null}
            onClick={() => onSelectAgent(null)}
            title={collapsed ? "All messages" : undefined}
          >
            <span className="agent-dot agent-dot--all" />
            <span className="agent-card__content">
              <span className="agent-card__title">All messages</span>
              <span className="agent-card__meta">{totalMessages} event(s)</span>
            </span>
          </button>
        </li>
        {agents.map((agent) => (
          <li key={agent.id}>
            <button
              type="button"
              className={`agent-card${selectedAgentId === agent.id ? " is-active" : ""}`}
              aria-pressed={selectedAgentId === agent.id}
              onClick={() => onSelectAgent(agent.id)}
              title={collapsed ? agent.label : undefined}
            >
              <span
                className="agent-dot"
                style={{ "--agent-color": agent.color }}
              />
              <span className="agent-card__content">
                <span className="agent-card__title">{agent.label}</span>
                <span className="agent-card__meta">
                  {agent.ref || agent.type || "surface"} - {agent.eventCount} event(s)
                </span>
              </span>
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
