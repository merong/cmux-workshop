# Repository Guidelines

## Project Structure & Module Organization

This repository packages the `cmux-workshop` Claude Code plugin. The shipped plugin lives under `plugins/cmux-workshop/`. Key areas are `agents/` for persona prompts, `commands/` for slash-command shims, `hooks/` for Bash PreToolUse hooks, `tools/` for SQLite helpers and SQL queries, and `skills/` for plugin skills. The `/project-view` runtime is vendored at `plugins/cmux-workshop/skills/project-view/runtime/`; its React client is in `client/src/`, server code in `server.js`, and parser utilities in `lib/`. Top-level docs include `README.md`, `README-ko.md`, and `CLAUDE.md`.

## Build, Test, and Development Commands

Run runtime commands from `plugins/cmux-workshop/skills/project-view/runtime/`.

- `npm install`: install vendored runtime dependencies.
- `npm run build`: build the React bundle into `runtime/dist/`.
- `npm start`: run the Express/WebSocket dashboard server.
- `npm run dev`: start the Vite development server for the React client.
- `bash plugins/cmux-workshop/skills/project-view/scripts/check-deps.sh`: verify Redis, Node, and runtime structure.
- `bash plugins/cmux-workshop/skills/project-view/scripts/start.sh`: build if needed, start the dashboard, and print the ready URL.

## Coding Style & Naming Conventions

Use existing style: two-space indentation in JavaScript/JSX, double quotes, semicolons, PascalCase React components, and `use*` hook names. Shell scripts should use `#!/usr/bin/env bash`, `set -euo pipefail`, kebab-case filenames, and quote paths. SQL migrations use numbered filenames such as `003_session_tracking.sql`; reusable SQL lives in `tools/queries/`.

## Testing Guidelines

There is no CI and `npm test` is currently a placeholder that fails. Validate changes manually with focused checks: `npm run build` for runtime UI changes, `bash -n` for edited shell scripts, JSON parsing for plugin manifests, and `check-deps.sh` for launcher assumptions. For end-to-end verification, run `start.sh` and confirm `READY: http://localhost:11573` or the configured port.

## Commit & Pull Request Guidelines

Commit history uses Conventional Commit style: `feat(project-view): ...`, `fix(project-view): ...`, `docs(ko): ...`, `chore: ...`; use `!` for breaking changes. PRs should describe behavior changes, list verification commands, link related issues, and include screenshots for visible dashboard changes.

## Security & Configuration Tips

Do not commit `node_modules/`, `dist/`, local `.claude/project.db`, logs, or PID files. Any change under `plugins/cmux-workshop/` must bump both plugin manifests in lockstep: `.claude-plugin/marketplace.json` and `plugins/cmux-workshop/.claude-plugin/plugin.json`. Preserve `plugins/cmux-workshop/AGENTS.md`; it is a copied hand-off contract, not this contributor guide.
