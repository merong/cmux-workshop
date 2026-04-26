# cmux-workshop

A unified Claude Code plugin that combines:

1. **`/project-view`** — a one-shot launcher for the bundled cmux monitor
   (socket proxy + Express/Socket.io server + Vite/React dashboard +
   terminal polling). Opens `http://localhost:13331` automatically.
2. The full **project-workspace toolchain** ported from the upstream
   `upstar` plugin: eight skills, project slash-command shims, three code
   slash commands, six agent personas,
   shared SQLite tooling, and PreToolUse security hooks.

Everything lives in a single self-contained plugin: `plugins/cmux-workshop/`.

## Layout

```
cmux-workshop/
├── .claude-plugin/marketplace.json     # marketplace entry
├── .claude/settings.json               # enables this plugin locally
├── plugins/cmux-workshop/
│   ├── .claude-plugin/plugin.json
│   ├── agents/                         # 6 personas (orchestrator, implementer,
│   │                                   #   reviewer, architect, debugger,
│   │                                   #   researcher)
│   ├── commands/                       # project-* shims + code commands
│   │   ├── project-{init,agent,reload,reset,status,view,view-stop}.md
│   │   ├── code-quality.md
│   │   ├── code-explore.md
│   │   └── merge-permissions.md
│   ├── hooks/
│   │   ├── hooks.json                  # PreToolUse(Bash) chain
│   │   └── scripts/
│   │       ├── block-dangerous.sh      # rm -rf / force-push guard
│   │       └── save-conv-before-commit.sh
│   ├── tools/                          # shared SQLite (db.sh + schema.sql)
│   │   ├── db.sh
│   │   ├── schema.sql
│   │   ├── queries/                    # reusable read queries
│   │   └── scripts/                    # project-info-{capture,show}.sh
│   └── skills/
│       ├── project-view/               # ⬅ NEW — one-shot monitor launcher
│       │   ├── SKILL.md
│       │   ├── scripts/                # start.sh, check-deps.sh, helpers.sh
│       │   ├── runtime/                # vendored cmux-monitor full stack
│       │   └── references/             # architecture + troubleshooting
│       ├── cmux/                       # cmux terminal control
│       ├── save-conversation/
│       ├── project-init/               # phase 1 — PRD bootstrap
│       ├── project-agent/              # phase 2 — agent composition
│       ├── project-reload/             # phase 3 — cmux pane deploy
│       ├── project-reset/
│       └── project-status/
├── README.md (this file)
└── CLAUDE.md
```

## Quick start: monitor

```
/project-view
```

…dependency check → proxy inject → web dev server → terminal polling →
opens `http://localhost:13331`.

### Prerequisites (one-time, manual)

The skill detects these and prints install hints if anything is missing —
it never auto-installs.

```bash
# cmux app — must already be installed and running
brew install redis && brew services start redis
brew install node                      # >= 18

pip3 install -r plugins/cmux-workshop/skills/project-view/runtime/requirements.txt
( cd plugins/cmux-workshop/skills/project-view/runtime/web && npm run install:all )
```

### Stop the monitor

```
/project-view-stop
```

The command kills only launcher-owned PID files, restores the vendored proxy,
cleans launcher logs, and verifies `cmux ping`.

PID and log files keep the `cmux-workshop-` prefix because they belong to
the plugin as a whole, not to the `project-view` skill specifically.

## Skill catalog

| Skill | What it does |
|---|---|
| `project-view` | One-shot launch the cmux monitor + open dashboard |
| `cmux` | Direct cmux terminal/pane/notification control |
| `save-conversation` | Persist conversation summary to markdown |
| `project-init` | Phase 1 — brainstorm + PRD + `.claude/project.db` bootstrap |
| `project-agent` | Phase 2 — compose AI agent personas, write `.claude/agents/` |
| `project-reload` | Phase 3 — deploy/restore agents to cmux panes |
| `project-reset` | Tear down panes/agents/PRD (full or partial) |
| `project-status` | Show workflow phase + live agent status |

## Slash commands

| Command | Purpose |
|---|---|
| `/project-init` | Phase 1 — brainstorm + PRD + `.claude/project.db` bootstrap |
| `/project-agent` | Phase 2 — compose AI agent personas |
| `/project-reload` | Phase 3 — deploy/restore agents to cmux panes |
| `/project-reset` | Tear down panes/agents/PRD (full or partial) |
| `/project-status` | Show workflow phase + live agent status |
| `/project-view` | Launch the cmux monitor + open dashboard |
| `/project-view-stop` | Stop the monitor/proxy stack |
| `/code-quality` | Score code on 9 dimensions via parallel agents |
| `/code-explore` | Deep multi-agent codebase analysis |
| `/merge-permissions` | Merge local `.claude/settings.local.json` into global |

## Hooks (PreToolUse on Bash)

- `block-dangerous.sh` — refuses `rm -rf`, force-push to main/master, etc.
- `save-conv-before-commit.sh` — forces saving conversation before any
  `git commit`. Triggers `cmux-workshop:save-conversation`.

## Shared tooling

All project-* skills persist state in `.claude/project.db` (SQLite).
`plugins/cmux-workshop/tools/db.sh` is the canonical wrapper:

```bash
tools/db.sh migrate
tools/db.sh init
tools/db.sh exists
tools/db.sh query  "SELECT * FROM agents"
tools/db.sh json   "SELECT * FROM agents"
tools/db.sh exec   "UPDATE progress SET completed=1 WHERE phase='prd'"
tools/db.sh run    queries/reset-local.sql
```

Override the DB path with `CMUX_WORKSHOP_DB_PATH`. Enable trace logging
with `CMUX_WORKSHOP_DEBUG=1`.

## Where to look when things break

- `plugins/cmux-workshop/skills/project-view/references/troubleshooting.md`
- `/tmp/cmux-workshop-web.log`
- `/tmp/cmux-workshop-polling.log`
- `/tmp/cmux-proxy.log`
