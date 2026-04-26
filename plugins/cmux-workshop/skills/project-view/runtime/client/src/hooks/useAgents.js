import { useMemo } from "react";

const COLORS = [
  "#58a6ff", "#3fb950", "#d29922", "#bc8cff",
  "#f778ba", "#79c0ff", "#56d364", "#e3b341",
];

/**
 * useAgents(messages, surfacesById?) — derive agent list + color map.
 * INVARIANT: first-seen is registered in chronological message order, once.
 * Colors stay stable across renders; only the label resolves against the
 * latest surfacesById (cmux title). Fallback to the first 8 chars of
 * surface_id when cmux metadata is missing.
 */
export function useAgents(messages, surfacesById) {
  const agentsById = useMemo(() => {
    const nextAgents = new Map();

    for (const msg of messages) {
      const surfaceId = msg.surface_id;
      if (!surfaceId || nextAgents.has(surfaceId)) continue;

      const meta = surfacesById?.get(surfaceId);
      nextAgents.set(surfaceId, {
        id: surfaceId,
        color: COLORS[nextAgents.size % COLORS.length],
        label: meta?.title || surfaceId.substring(0, 8),
        ref: meta?.ref || "",
        type: meta?.type || "",
      });
    }

    return nextAgents;
  }, [messages, surfacesById]);

  const agents = useMemo(() => Array.from(agentsById.values()), [agentsById]);

  return { agents, agentsById };
}
