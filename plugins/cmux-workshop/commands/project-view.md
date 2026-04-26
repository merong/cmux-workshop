---
description: Launch the project-view monitor and open the ready dashboard URL
argument-hint: ""
allowed-tools: Bash
model: opus
---

Run `OUT=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/project-view/scripts/start.sh"); printf '%s\n' "$OUT"; URL=$(printf '%s\n' "$OUT" | sed -n 's/^READY: //p' | tail -n 1); [ -n "$URL" ] && open "$URL"`.
