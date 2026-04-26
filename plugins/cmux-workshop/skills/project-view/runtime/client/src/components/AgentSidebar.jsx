import React from "react";

export default function AgentSidebar({ agents }) {
  return (
    <aside className="agent-sidebar">
      <h3>Agents</h3>
      <ul>
        {agents.map((agent) => (
          <li key={agent.id}>
            <span
              className="agent-dot"
              style={{ "--agent-color": agent.color }}
            />
            {agent.label}
          </li>
        ))}
      </ul>
    </aside>
  );
}
