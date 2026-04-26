import { useEffect, useState } from "react";

/**
 * useWorkspaceSurfaces — fetch cmux surface metadata for a workspace
 * and return it as Map<surfaceId, {title, ref, type}>.
 *
 * Source: GET /api/workspaces returns cmux_surfaces per workspace.
 * The map lets message components resolve msg.surface_id → human title
 * (e.g. "Claude Code", "Frontend", "Reviewer") instead of showing UUIDs.
 *
 * Retry: cmux RPC can return an empty surface list intermittently. We retry
 * up to 3 times with a short backoff when we get back zero surfaces.
 */
const RETRY_DELAYS_MS = [1500, 3000, 5000];

export function useWorkspaceSurfaces(workspaceId) {
  const [surfacesById, setSurfacesById] = useState(() => new Map());

  useEffect(() => {
    if (!workspaceId) {
      setSurfacesById(new Map());
      return;
    }
    const controller = new AbortController();
    let timer = null;
    let attempt = 0;

    const run = async () => {
      try {
        const r = await fetch("/api/workspaces", { signal: controller.signal });
        const list = await r.json();
        const ws = Array.isArray(list)
          ? list.find((w) => w.workspace_id === workspaceId)
          : null;
        const map = new Map();
        for (const s of ws?.cmux_surfaces || []) {
          if (!s?.id) continue;
          map.set(s.id, { title: s.title || "", ref: s.ref || "", type: s.type || "" });
        }
        setSurfacesById(map);
        if (map.size === 0 && attempt < RETRY_DELAYS_MS.length) {
          const delay = RETRY_DELAYS_MS[attempt++];
          timer = setTimeout(run, delay);
        }
      } catch (err) {
        if (err.name !== "AbortError") {
          setSurfacesById(new Map());
        }
      }
    };

    run();
    return () => {
      controller.abort();
      if (timer) clearTimeout(timer);
    };
  }, [workspaceId]);

  return surfacesById;
}
