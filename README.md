# cmux-workshop

> A Claude Code plugin that aligns **agent orchestration + real-time visualization** on top of the cmux terminal foundation, in a single unified package.

The cracks you don't notice with a single coding agent become loud the moment you run two or three at once. Instead of papering over those cracks with yet another tool, this project lays a **thin layer** on top of cmux — a terminal that already does most of what we need — and tries to align everything we already had.

```
/project-init    →  /project-agent   →  /project-reload  →  /project-view
   plan + PRD        agent team         cmux deploy         monitor + browser
```

> Looking for the Korean original? See [README-ko.md](./README-ko.md).

---

## At a Glance — Screenshots & Demo

### Screenshots

![Workspace selector](docs/images/01-workspace-selector.png)
*Workspace selector view. The cmux sidebar and a Claude Code terminal (running `/project-init`) on the left; on the right, the CMUX Workshop dashboard immediately picks up the freshly bootstrapped project as a workspace card enriched from `project.db` (project_name · git branch · phase progress · listening ports).*

![project-init and chat timeline](docs/images/02-project-init-and-chat.png)
*Right after `/project-reload` deploys the personas (orchestrator · implementer · reviewer) into cmux panes. While Claude Code drives the work on the left, the redis-chat-ui dashboard on the right surfaces hook events (prompt-submit · tool call · stop) as a per-workspace chat timeline in real time.*

![Multi-agent activity](docs/images/03-multi-agent-activity.png)
*Four cmux panes (Claude Code · Orchestrator · Implementer · Reviewer) running concurrently. The "All messages / per-agent" cards in the right sidebar let you filter the timeline down to a single surface, and each card shows the accumulated event count.*

### Demo videos

Recorded live demos live in this Google Drive folder:

→ [cmux-workshop demo videos (Google Drive)](https://drive.google.com/drive/folders/1ajLLNxfW3IxUBGWOwxxiopVDGCloj2u1?usp=drive_link)

Included clips:
- **`cmux-agent-create`** — the full path from `/project-init` → `/project-agent` → `/project-reload`, creating a new multi-agent workspace.
- **`cmux-agent-done`** — the deployed agent team finishing its work, with the results reflected in both the chat timeline and the cmux pane tree.

---

## Starting point — the small cracks in agent orchestration

If you have ever pointed several agents at a single project, this scenery should feel familiar.

| Friction you keep meeting | Why it actually hurts |
|---|---|
| **Context evaporates** | Once the session ends, the trail of "who decided what, and why" is gone. Tomorrow you start over from the same spot. |
| **State only lives in your head** | "Where is the PRD again?", "Which folder holds the agent definitions?", "Who is sitting in which pane?" — all kept alive by sheer human memory. |
| **The tools don't talk to each other** | Brainstorming uses one skill, persona definitions sit in another file, the actual run happens in the terminal, monitoring uses a separate CLI — every tool has a different mental model. |
| **You can't see what is happening behind the curtain** | To check what an agent threw at the cmux socket, or which pane has stalled, you end up dumping the socket by hand. |
| **It is not reproducible** | The workspace layout that worked yesterday cannot be brought back today. You re-split the panes by hand. |
| **There is no safety net** | The promise to "save the conversation just before `git commit`" gets forgotten every time, and dangerous commands only get regretted right after they execute. |

Each of those frictions has plenty of solutions on the market. The real problem is that **none of them flow naturally inside one workflow**.

---

## The path we chose

**We do not build a new terminal.** cmux already gives us the native environment a coding agent needs — vertical tabs, split panes, an embedded browser, a JSON-RPC socket, notifications. cmux-workshop drops a **thin consistency layer** on top of that foundation.

```mermaid
flowchart LR
    subgraph cmux["cmux (native terminal + socket)"]
        TUI[Workspace · Pane · Surface]
        Sock[(JSON-RPC Socket)]
    end

    subgraph Wrap["cmux-workshop layer"]
        direction TB
        Skills["Skills<br/>(staged workflow)"]
        State[("project.db<br/>state persistence")]
        WebUI["Web Dashboard<br/>(live visibility)"]
        Hooks["PreToolUse<br/>(safety net)"]
    end

    User[Developer]
    Browser[Browser]

    User <--> Skills
    Skills --> TUI
    Skills <--> State
    Skills --> Sock
    Sock -. mirror traffic .-> WebUI
    WebUI --> Browser
    Browser --> User
    Hooks -. guard .-> Skills
```

The layer does only five things.

1. **Stage** — the fuzzy notion of "agent setup" is broken into four slash commands: `init → agent → reload → view`.
2. **Persist** — every decision and layout lands in a single `.claude/project.db` SQLite file. Volatility removed.
3. **Delegate** — creative divergence is handed to a proven external skill (`superpowers:brainstorming`); we just take the result and shape it into a PRD. Clear separation of responsibility.
4. **Visualize** — cmux socket traffic is mirrored through a transparent proxy into Redis Streams and immediately surfaced in a web dashboard.
5. **Reproduce** — yesterday's pane layout can be brought back today with the exact same command.

Each piece is a small decision; together they make "working alongside agents" feel one notch smoother.

---

## Why a single bundled plugin

Letting a user assemble eight loose skills on their own is one thing. Wrapping them inside a single marketplace entry that shares the same naming scheme, the same DB, and the same monitor is something else entirely.

| Loose collection of skills | Bundled into one plugin |
|---|---|
| Each skill has its own namespace, DB location, and env vars | One `cmux-workshop:*` namespace · `CMUX_WORKSHOP_DB_PATH` · shared PID/log prefix |
| The user picks which skill to call first, every time | `project-status` reports "what to call next" in one line |
| Monitor / proxy / web server set up by hand | `/project-view` runs the dependency check, boots, and opens the browser in one shot |
| Safety hooks registered manually | `hooks.json` activates the `PreToolUse` guard the moment the plugin is enabled |
| Repository clone + lots of follow-up configuration | Just enable the marketplace entry — the vendored runtime is already in place |

Because the **plugin is the single carrier**, the user can switch the entire workflow on or off as one unit. Consistency itself is productivity.

---

## Effect — what actually shrinks

The same task in two flavors.

| Task | Common flow | cmux-workshop flow |
|---|---|---|
| Bootstrap a new project | brainstorm tool → notes → write PRD by hand → write personas by hand → split cmux panes manually → inject persona into each pane manually | `/project-init` → `/project-agent` → `/project-reload` (three slashes) |
| Resume the next day | "Where was I again?" → dig through scattered files → rebuild the working environment | `/project-status` → call the suggested next skill |
| Restore after cmux restart | Recreate yesterday's layout by hand | `/project-reload` once |
| Debug traffic | Attach to the socket and dump · grep log files | `/project-view` → live in the browser |
| Tear down a workspace | Close panes by hand + delete files | `/project-reset` (partial or full) |
| Save the conversation before `git commit` | You have to remember it every time | The PreToolUse hook enforces it automatically |

**The point isn't "how much faster" but "how much less you have to remember."** Less state in your head means more headroom for the actual problem.

---

## User-friendliness — what the tool asks of the user

A good tool shrinks the list of things you have to memorize. The rules cmux-workshop deliberately follows.

- **Single entry point** — every common action starts with one `/project-*` slash command. Even shutting down the monitor stays inside the same naming scheme: `/project-view-stop`.
- **Natural-language triggers** — alongside `/project-view`, phrases like "project view", "cmux chat view", or "see claude code activity" route to the same skill. You don't have to memorize the exact command.
- **Guidance instead of installation** — when a dependency is missing the plugin prints `brew install ...` instead of installing anything. Nothing gets put on your machine without you knowing.
- **Idempotent calls** — re-launching an already-running monitor is safe; the browser just gets re-opened.
- **State guidance first** — `project-status` always tells you "what to do next." You don't have to memorize the whole workflow.
- **Consistent output** — every script log carries the `[cmux-workshop]` prefix; the browser URL, PID file, and stop command all show up in the same line.

> "How it should work." — the tool explains itself without you having to learn it separately.

---

## The workflow in one diagram

```mermaid
flowchart LR
    Start([new project])

    subgraph Phase1["Phase 1 · Plan"]
        I["/project-init"]
        BS[("superpowers:<br/>brainstorming")]
        PRD[(".claude/PRD.md")]
        I --> BS --> PRD
    end

    subgraph Phase2["Phase 2 · Team"]
        A["/project-agent"]
        Lib[("local 6 +<br/>VoltAgent")]
        Per[(".claude/agents/")]
        A --> Lib --> Per
    end

    subgraph Phase3["Phase 3 · Deploy"]
        R["/project-reload"]
        DB[("project.db<br/>layout_splits")]
        Panes[("cmux<br/>Workspace · Pane · Surface")]
        R --> DB --> Panes
    end

    subgraph Ops["Operate · Observe"]
        V["/project-view"]
        Mon[("redis-chat-ui<br/>express + ws")]
        UI[("browser<br/>localhost:11573")]
        S["/project-status"]
        V --> Mon --> UI
    end

    Start --> Phase1 --> Phase2 --> Phase3 --> Ops
    Phase3 -.anytime.-> S
    Ops -.anytime.-> S
```

---

## System architecture

```mermaid
flowchart LR
    User[Developer]
    ClaudeCode[Claude Code]

    subgraph Plugin["cmux-workshop plugin"]
        direction TB
        Skills[skills/]
        Commands[commands/]
        Agents[agents/]
        Hooks[hooks/]
        Tools[tools/db.sh]
    end

    subgraph State[".claude/ (project state)"]
        PRD[PRD.md]
        DB[(project.db<br/>SQLite)]
        AgentFiles[agents/*.md]
    end

    subgraph cmuxApp["cmux app"]
        Sock[(cmux.sock<br/>JSON-RPC)]
        Panes[Workspace · Pane · Surface]
    end

    subgraph Monitor["project-view runtime"]
        Producers[("Claude Code hooks<br/>(prompt-submit · stop · idle ·<br/>pre/post-tool-use)")]
        Redis[("Redis Stream<br/>cmux:hooks")]
        WebSrv[express + WebSocket<br/>server.js]
        UI[React 19<br/>localhost:11573]
    end

    User -->|"/project-* call"| ClaudeCode
    ClaudeCode --> Skills
    Skills --> Tools
    Tools <--> DB
    Skills --> PRD
    Skills --> AgentFiles
    Skills -->|"cmux CLI"| Sock
    Sock --> Panes

    ClaudeCode -.hook events.-> Producers
    Producers --> Redis
    Redis --> WebSrv
    WebSrv -.WebSocket.-> UI
    WebSrv -.cmux rpc.-> Sock
    UI -->|"browser"| User

    Hooks -.PreToolUse.-> ClaudeCode
```

The plugin bridges three regions: **state (.claude/)**, the **cmux app (socket)**, and the **project-view runtime (redis-chat-ui)**. Every skill works on top of the same `tools/db.sh`, so they all share one consistent SQLite schema.

---

## Scenario 1 — Bootstrapping a new project

From an empty directory to a cmux screen where agents can actually start working — in four steps.

```mermaid
flowchart TD
    Start([new project directory])
    Init["/project-init"]
    Brainstorm["superpowers:brainstorming<br/>(mandatory delegation)"]
    PRDFile[".claude/PRD.md written"]
    DBPhase1[("progress.prd = 1<br/>project.db")]

    Agent["/project-agent"]
    Personas{"Read PRD:<br/>which roles do we need?"}
    LocalLib[plugins/cmux-workshop/agents/<br/>local 6-persona library]
    VoltAgent[VoltAgent<br/>awesome-claude-code-subagents]
    AgentFiles[".claude/agents/*.md<br/>customized + copied"]
    DBPhase2[("agents + layout_splits<br/>progress.agents = 1")]

    Reload["/project-reload"]
    CmuxAPI{{cmux Socket API}}
    NewPanes[new Workspace +<br/>pane splits + Surface]
    Inject[persona injection<br/>CLAUDE_PROFILE]
    DBPhase3[("local_workspace +<br/>local_surfaces<br/>progress.deployed = 1")]

    View["/project-view"]
    MonitorUp[redis-chat-ui server ON<br/>express + WebSocket]
    Browser[("browser opens automatically<br/>localhost:11573")]

    Start --> Init
    Init --> Brainstorm
    Brainstorm --> PRDFile
    PRDFile --> DBPhase1
    DBPhase1 --> Agent
    Agent --> Personas
    Personas -->|"existing roles enough"| LocalLib
    Personas -->|"need new role"| VoltAgent
    LocalLib --> AgentFiles
    VoltAgent --> AgentFiles
    AgentFiles --> DBPhase2
    DBPhase2 --> Reload
    Reload --> CmuxAPI
    CmuxAPI --> NewPanes
    NewPanes --> Inject
    Inject --> DBPhase3
    DBPhase3 --> View
    View --> MonitorUp
    MonitorUp --> Browser
```

**Outputs**: one PRD, N agent personas, a cmux pane tree, a live dashboard.

---

## Scenario 2 — Brainstorming the agent team

The internal collaboration between `project-init` and `project-agent`, drawn as a sequence. **User decisions** and **AI delegation** are clearly separated.

```mermaid
sequenceDiagram
    actor U as Developer
    participant CC as Claude Code
    participant PI as project-init
    participant SB as superpowers:<br/>brainstorming
    participant PA as project-agent
    participant DB as project.db
    participant FS as .claude/

    U->>CC: /project-init
    CC->>PI: invoke
    PI->>DB: bootstrap project_info
    PI->>SB: delegate (mandatory)

    rect rgb(245, 245, 220)
        note over SB,U: brainstorming checklist
        SB->>U: ask intent / constraints / success criteria
        U-->>SB: answer
        SB->>U: compare 2~3 approaches + recommendation
        U-->>SB: pick
        SB->>U: present design (section by section)
        U-->>SB: final approval
    end

    SB-->>PI: approved design
    PI->>FS: write PRD.md
    PI->>DB: progress.prd = 1
    PI-->>U: "next: /project-agent"

    U->>CC: /project-agent
    CC->>PA: invoke
    PA->>FS: read PRD.md
    PA->>U: propose persona mix

    rect rgb(225, 240, 255)
        note over PA,U: agent curation
        loop per role
            U-->>PA: pick (local 6 or VoltAgent search)
            PA->>FS: copy agents/<role>.md + inject PRD context
            PA->>DB: record binding in agents table
        end
        PA->>DB: write layout_splits recipe
    end

    PA->>DB: progress.agents = 1
    PA-->>U: "next: /project-reload"
```

**Key design**: `project-init` **does not ask for ideas itself.** All creative divergence is delegated to the proven `superpowers:brainstorming` skill, and only its output is persisted as a PRD. Responsibility between tools stays cleanly separated.

---

## Scenario 3 — Auto-deploying cmux terminal panes

The multi-pane screen that `project-reload` creates. The `layout_splits` recipe in `.claude/project.db` is replayed verbatim through the cmux Socket API.

```mermaid
flowchart LR
    subgraph DBSrc["project.db"]
        Layout["layout_splits<br/>(direction, ratio, order)"]
        AgentBind["agents<br/>(role, persona path)"]
    end

    subgraph Reload["project-reload run"]
        Read[read DB]
        Verify[verify existing surfaces]
        Plan[build deployment plan]
        Apply[invoke cmux CLI]
    end

    subgraph CmuxLayout["resulting cmux workspace"]
        direction TB
        WS["Workspace<br/>(sidebar tab)"]
        subgraph PaneA["Pane A (left)"]
            SurfaceA1["Surface: orchestrator"]
        end
        subgraph PaneB["Pane B (right top)"]
            SurfaceB1["Surface: implementer"]
        end
        subgraph PaneC["Pane C (right bottom)"]
            SurfaceC1["Surface: reviewer"]
        end
        WS --- PaneA
        WS --- PaneB
        WS --- PaneC
    end

    DBSrc --> Read
    Read --> Verify
    Verify --> Plan
    Plan --> Apply
    Apply -->|cmux new-workspace| WS
    Apply -->|cmux new-split right| PaneA
    Apply -->|cmux new-split down| PaneB
    Apply -->|cmux new-split down| PaneC
    Apply -->|cmux send + CLAUDE_PROFILE| SurfaceA1
    Apply -->|cmux send + CLAUDE_PROFILE| SurfaceB1
    Apply -->|cmux send + CLAUDE_PROFILE| SurfaceC1

    Apply -.record.-> LocalSrf[(local_surfaces<br/>pane_id, surface_id)]
```

**Recovery is the same flow.** After cmux restarts and every pane is gone, calling `/project-reload` again replays the same recipe into the same shape. **Reproducibility** is the point.

---

## Scenario 4 — Live observation: project-view (redis-chat-ui)

After deployment, when you want a chat-style view of "what hook events (prompt-submit, tool calls, stop/idle) are flowing between the user and the agents right now."

```mermaid
sequenceDiagram
    actor U as Developer
    participant CC as Claude Code
    participant Hooks as cmux-workshop hooks<br/>(PreToolUse · PostToolUse ·<br/>session lifecycle)
    participant PV as project-view (start.sh)
    participant Dep as check-deps.sh
    participant Build as npm run build<br/>(once if needed)
    participant Srv as runtime/server.js<br/>(express + ws)
    participant R as Redis Stream<br/>cmux:hooks
    participant CS as cmux.sock
    participant B as Browser

    par always running
        CC->>Hooks: tool/session events
        Hooks->>R: XADD cmux:hooks (+ HSET detail Hash)
    end

    U->>CC: /project-view
    CC->>PV: invoke (start.sh)
    PV->>Dep: check redis / node / npm / runtime/node_modules
    Dep-->>PV: all OK
    PV->>Build: vite build if dist/index.html missing
    Build-->>PV: dist/ produced
    PV->>Srv: nohup PORT=11573 node server.js
    Srv->>R: XREVRANGE / XREAD cmux:hooks
    Srv->>CS: cmux rpc workspace.list / surface.list (metadata)
    PV->>Srv: curl localhost:11573 (60s health probe)
    Srv-->>PV: 200 OK
    PV-->>CC: "READY: http://localhost:11573"
    CC->>B: open URL
    B->>Srv: GET /  (serves static dist)
    B<<->>Srv: WebSocket /ws  (live hook event stream)
    B-->>U: per-workspace chat timeline
```

**What you can observe**: prompt-submit / pre-tool-use / post-tool-use / stop / idle events grouped by workspace, tool call input/response previews, and workspace titles + colors enriched via cmux RPC.

---

## Scenario 5 — Daily development lifecycle

The day after the project has already been set up — the flow for picking the work back up.

```mermaid
stateDiagram-v2
    [*] --> Start
    Start --> CheckStatus: /project-status
    CheckStatus --> Decide

    state Decide <<choice>>
    Decide --> NewBootstrap: progress.deployed = 0
    Decide --> Restore: panes are gone<br/>(cmux restart, etc.)
    Decide --> Running: all healthy

    NewBootstrap --> Init: /project-init
    Init --> Agent: /project-agent
    Agent --> Reload: /project-reload
    Reload --> Running

    Restore --> Reload2: /project-reload
    Reload2 --> Running

    Running --> StartMonitor: /project-view
    StartMonitor --> Work
    Work --> CmuxCtrl: /cmux<br/>(add panes, notify)
    CmuxCtrl --> Work
    Work --> SaveConv: /save-conversation
    SaveConv --> End

    Running --> NeedsChange
    NeedsChange --> Reset: /project-reset<br/>(partial / full)
    Reset --> Start

    End --> [*]
```

**The entry point is always `/project-status`** — one line tells you where to pick up.

---

## Scenario 6 — Safety net: PreToolUse hook

A two-stage guard that runs right before every Bash tool call.

```mermaid
flowchart LR
    BashCall[["Claude tries to call Bash"]]
    Block["block-dangerous.sh"]
    Save["save-conv-before-commit.sh"]
    Allow{Allow?}
    Run([Bash runs])
    Reject([blocked + guidance])
    InvokeSC[["Skill: cmux-workshop:<br/>save-conversation"]]

    BashCall --> Block
    Block -->|"rm -rf, force-push, etc."| Reject
    Block -->|safe| Save
    Save -->|"is git commit?"| InvokeSC
    InvokeSC -->|after saving conversation| Allow
    Save -->|"not a git commit"| Allow
    Allow --> Run
```

The hook is wired in via `hooks.json` and is active automatically while the cmux-workshop plugin is enabled. The user does not have to set anything up.

---

## Repository layout

```
cmux-workshop/
├── .claude-plugin/marketplace.json     # marketplace entry
├── .claude/settings.json               # local plugin enablement
├── plugins/cmux-workshop/
│   ├── .claude-plugin/plugin.json      # plugin metadata
│   ├── agents/                         # 6 personas (orchestrator, implementer,
│   │                                   #   reviewer, architect, debugger, researcher)
│   ├── commands/                       # /project-* shims + code commands
│   ├── hooks/                          # PreToolUse guards
│   │   ├── hooks.json
│   │   └── scripts/{block-dangerous,save-conv-before-commit}.sh
│   ├── tools/                          # shared SQLite plumbing (db.sh + schema.sql)
│   │   ├── db.sh                       # init / query / json / scalar / exec / run / quote
│   │   ├── schema.sql                  # project / progress / prd / agents / layout_splits ...
│   │   ├── queries/                    # reusable SQL
│   │   └── scripts/project-info-{capture,show}.sh
│   └── skills/
│       ├── project-view/               # one-shot launcher (vendored redis-chat-ui)
│       │   ├── SKILL.md
│       │   ├── scripts/{start,stop,check-deps,helpers}.sh
│       │   ├── runtime/                # vendored copy of the redis-chat-ui stack
│       │   │   ├── server.js           # express + WebSocket + redis stream consumer
│       │   │   ├── vite.config.js      # build-time only
│       │   │   ├── package.json · package-lock.json
│       │   │   ├── lib/parser.js       # stream-record normalization
│       │   │   └── client/             # React 19 (App.jsx, components, hooks, styles)
│       │   └── references/{architecture,troubleshooting}.md
│       ├── cmux/                       # direct cmux control (split/notify/browser)
│       ├── save-conversation/          # write conversation markdown
│       ├── project-init/               # Phase 1 — PRD bootstrap
│       ├── project-agent/              # Phase 2 — assemble agent team
│       ├── project-reload/             # Phase 3 — cmux deploy/restore
│       ├── project-status/             # status check (callable any time)
│       └── project-reset/              # cleanup (partial / full)
├── README.md / README-ko.md            # ← you are here
└── CLAUDE.md
```

## State persistence — the `project.db` schema

Folding the volatile state we used to keep in our heads into a single file is the spine of this plugin. Every skill works through the same `tools/db.sh` and shares the same SQLite schema.

### Two zones

| Zone | Tables | Intent |
|---|---|---|
| **Portable (git-safe)** | `project`, `progress`, `prd`, `agents`, `layout_splits`, `project_info`, `metadata` | "What are we building / who is responsible," shared by the team. Safe to commit. |
| **Machine-local** | `local_workspace`, `local_surfaces`, `local_kv` | "Which IDs do this machine's cmux panes hold right now." Changes on every cmux restart. |

The split lets you **share the PRD and agent definitions in git** while keeping per-machine runtime IDs (workspace/pane/surface) out of band.

### Tables at a glance

| Table | Rows | Core role |
|---|---|---|
| `project` | single (`id=1`) | display name · description · creation timestamp |
| `progress` | exactly 3 | completion flag (0/1) for the `prd` / `agents` / `deployed` phases |
| `prd` | single | relative path to `.claude/PRD.md` |
| `agents` | N | agent persona binding (role/model/file location/source) |
| `layout_splits` | N | cmux pane **replay recipe** (run order · split direction · base agent) |
| `project_info` | single | environment snapshot (project_root, cmux_workspace_id, git remote/branch) |
| `metadata` | KV | freeform extension slot |
| `local_workspace` | single | this machine's cmux workspace ID |
| `local_surfaces` | N | agent ↔ surface/pane ID mapping + status (`running`/`stopped`/`skipped`/`error`) |
| `local_kv` | KV | machine-local freeform extension slot |

### Relationships (ERD)

```mermaid
erDiagram
    project ||--|| progress : "phase tracking"
    project ||--o| prd : "single PRD"
    project ||--o{ agents : "team roster"
    agents ||--o{ layout_splits : "split recipe"
    agents ||--o| local_surfaces : "runtime binding"
    project ||--|| project_info : "environment snapshot"
    project ||--o| local_workspace : "cmux workspace"

    project {
        INTEGER id PK "= 1"
        INTEGER schema_version
        TEXT name
        TEXT description
        TEXT created_at
        TEXT updated_at
    }

    progress {
        TEXT phase PK "prd|agents|deployed"
        INTEGER completed "0|1"
        TEXT completed_at
    }

    prd {
        INTEGER id PK "= 1"
        TEXT path ".claude/PRD.md"
        TEXT created_at
    }

    agents {
        TEXT id PK
        TEXT name
        TEXT type "claude|codex|custom"
        TEXT role
        TEXT model
        TEXT agent_file ".claude/agents/*.md"
        TEXT source_type "local-library|voltagent|custom"
        TEXT source_origin
        TEXT launch_command
        TEXT cli_binary
        INTEGER is_caller "0|1"
        INTEGER position "display order"
    }

    layout_splits {
        INTEGER position PK "execution order"
        TEXT agent_id FK
        TEXT direction "left|right|up|down"
        TEXT from_agent_id "split origin"
    }

    project_info {
        INTEGER id PK "= 1"
        TEXT project_name
        TEXT project_summary
        TEXT project_root "absolute path"
        TEXT cmux_workspace_id
        TEXT cmux_workspace_title
        TEXT cmux_socket_path
        TEXT git_remote_url
        TEXT git_branch
        TEXT captured_at
        TEXT created_at
        TEXT updated_at
    }

    local_workspace {
        INTEGER id PK "= 1"
        TEXT workspace_id "cmux runtime id"
        TEXT created_at
        TEXT updated_at
    }

    local_surfaces {
        TEXT agent_id PK,FK
        TEXT surface_id
        TEXT pane_id
        TEXT tab_title
        TEXT status "running|stopped|skipped|error"
        TEXT updated_at
    }
```

### Skill × table responsibility matrix

| Table | `project-init` | `project-agent` | `project-reload` | `project-status` | `project-reset` |
|---|:-:|:-:|:-:|:-:|:-:|
| `project`, `project_info` | create | — | — | read | drop (full) |
| `progress.prd` | set 1 | — | — | read | set 0 |
| `prd` | write row | read | — | read | delete row |
| `agents` | — | upsert | read | read | delete rows |
| `layout_splits` | — | write | read | read | delete rows |
| `progress.agents` | — | set 1 | read | read | set 0 |
| `local_workspace` | — | — | upsert | read | delete |
| `local_surfaces` | — | — | upsert | read + reconcile vs cmux tree | delete |
| `progress.deployed` | — | — | set 1 | read | set 0 |

Each skill's permissions are kept narrow, so **it is always clear which skill changed which piece of state**.

### Design choices — why it looks like this

- **WAL disabled (`PRAGMA journal_mode = DELETE`)** — forces a single `.db` file. The `.db-wal` / `.db-shm` byproducts never sneak into git.
- **Foreign keys + `ON DELETE CASCADE`** — deleting a row in `agents` automatically removes its `layout_splits` and `local_surfaces`. `tools/db.sh` injects `PRAGMA foreign_keys=ON` on every sqlite connection, so partial resets stay safe.
- **`CHECK (id = 1)` on single-row tables** — `project`, `prd`, `project_info`, `local_workspace` are conceptually singletons. The constraint is encoded in the schema itself, so integrity bugs surface at compile time.
- **Pre-seeded rows** — the three `progress` phases are pre-inserted with `INSERT OR IGNORE`, so every subsequent `UPDATE` is guaranteed to hit a row.
- **Practical effect of the two-zone split** — PRD and agent specifications go into git in a code-reviewable form, while volatile cmux runtime IDs stay local. **Reproducibility + machine independence** at once.

### `tools/db.sh` cheatsheet

```bash
tools/db.sh migrate                         # initialize schema + apply pending migrations
tools/db.sh init                            # initialize schema only (idempotent; prefer migrate)
tools/db.sh exists                          # does the DB file exist
tools/db.sh path                            # absolute DB path
tools/db.sh query "SELECT * FROM agents"    # tabular (header + |-separated)
tools/db.sh json  "SELECT * FROM agents"    # JSON array
tools/db.sh scalar "SELECT completed FROM progress WHERE phase='prd'"
tools/db.sh exec  "UPDATE progress SET completed=1 WHERE phase='prd'"
tools/db.sh run   queries/reset-local.sql   # run from a file
tools/db.sh quote "user's input"            # SQL-safe escape
```

`CMUX_WORKSHOP_DB_PATH` overrides the DB path; `CMUX_WORKSHOP_DEBUG=1` sends an sqlite3 call trace to stderr.

---

## Skill catalog

| Skill | Phase | One-liner |
|---|---|---|
| `project-init` | 1 | invokes `superpowers:brainstorming`, turns the approved design into a PRD |
| `project-agent` | 2 | curates personas from the local 6-persona library + VoltAgent |
| `project-reload` | 3 | replays `project.db`'s layout_splits into cmux panes |
| `project-view` | ops | brings the proxy + web + polling stack up in one shot, opens the browser |
| `project-status` | aux | progress phases + live agent tree |
| `project-reset` | aux | safely roll back to any phase |
| `cmux` | aux | direct cmux CLI control (pane/notify/browser) |
| `save-conversation` | aux | dump the conversation as markdown under `conv-logs/YYYYMM/DD/` |

## Slash commands

| Command | Purpose |
|---|---|
| `/project-init` | Phase 1 — brainstorming + PRD + `.claude/project.db` bootstrap |
| `/project-agent` | Phase 2 — assemble the agent team |
| `/project-reload` | Phase 3 — cmux pane deploy / restore |
| `/project-reset` | clean up panes / agents / PRD partially or fully |
| `/project-status` | inspect progress phases + live agent state |
| `/project-view` | start the proxy + web + polling monitor and open the browser |
| `/project-view-stop` | stop the monitor / proxy stack |
| `/code-quality` | score code quality across 9 dimensions (parallel agents) |
| `/code-explore` | multi-agent deep dive into a codebase |
| `/merge-permissions` | merge local `.claude/settings.local.json` into the global one |

## Installing in Claude Code

cmux-workshop supports both **marketplace installation (recommended)** and **local clone**. Either way, the dependencies (redis, node, python redis, web packages) listed in [Quick start](#quick-start) must be in place — the plugin never installs them for you.

### Option 1 — Marketplace (recommended)

If you also want to use every skill / command / hook from other projects, the marketplace registration is cleanest. Run the following inside Claude Code, one after the other.

```
/plugin marketplace add merong/cmux-workshop
/plugin install cmux-workshop@cmux-workshop
```

After the install, restart Claude Code. Every slash command is then live (`/project-view`, `/project-init`, `/project-agent`, `/project-reload`, `/project-status`, `/project-reset`, `/project-view-stop`, `/code-quality`, `/code-explore`, `/merge-permissions`).

To check that the marketplace is registered:

```
/plugin
```

### Option 2 — Local clone (for contributing or in-place edits)

If you want to modify the plugin or test changes ahead of `main`, clone locally and let the bundled `.claude/settings.json` take care of enablement.

```bash
git clone https://github.com/merong/cmux-workshop.git
cd cmux-workshop
```

The repository's `.claude/settings.json` is already configured as below — no extra editing needed; just open Claude Code in this directory and the plugin auto-enables.

```json
{
  "enabledLocalPlugins": {
    "plugins/cmux-workshop/.claude-plugin": true
  }
}
```

If you want to use this local clone from another project, copy the same key into that project's `.claude/settings.json` and point `enabledLocalPlugins` at the absolute path.

### Verifying activation

```
/plugin                                    # inside Claude Code
```

You're done if `cmux-workshop` shows up as enabled. To inspect from a shell:

```bash
ls ~/.claude/plugins/marketplace/          # registered marketplaces
ls ~/.claude/plugins/cache/                # installed plugin cache
```

### Update / uninstall

```
/plugin update cmux-workshop@cmux-workshop
/plugin uninstall cmux-workshop@cmux-workshop
/plugin marketplace remove cmux-workshop
```

In local-clone mode, flip the corresponding key in `.claude/settings.json` to `false` (or remove it) to disable.

## Quick start

1. **One-time prep**

   ```bash
   # cmux app (must be running) + Redis + Node 18 + python redis + web deps
   brew install redis node && brew services start redis
   pip3 install -r plugins/cmux-workshop/skills/project-view/runtime/requirements.txt
   ( cd plugins/cmux-workshop/skills/project-view/runtime/web && npm run install:all )
   ```

2. **Enable the plugin** — follow [Installing in Claude Code](#installing-in-claude-code) using either the marketplace or the local-clone route.

3. **For a new project**

   ```
   /project-init     ← brainstorming + PRD
   /project-agent    ← assemble agent team
   /project-reload   ← cmux deploy
   /project-view     ← redis-chat-ui server + browser
   ```

4. **To resume**

   ```
   /project-status   ← check state
   /project-reload   ← restore if needed
   /project-view     ← bring project-view back up
   ```

## Operating notes

- PID/log: `/tmp/cmux-workshop-web.{pid,log}` (single `node server.js` process)
- Dashboard: `http://localhost:11573` (override with `CMUX_WORKSHOP_SERVER_PORT`)
- Stop: `/project-view-stop`
- Environment variables:
  - `CMUX_WORKSHOP_DB_PATH` (override DB path), `CMUX_WORKSHOP_DEBUG=1` (db.sh trace)
  - `CMUX_WORKSHOP_SERVER_PORT` (default 11573), `REDIS_URL` (default `redis://127.0.0.1:6379`), `STREAM_KEY` (default `cmux:hooks`)

## Design principles

1. **Self-contained vendor** — the entire `redis-chat-ui` stack is copied under `runtime/`. Zero dependency on external paths.
2. **Single namespace** — marketplace / plugin / env vars / PID / log all carry `cmux-workshop`. Skill names share the `project-*` family.
3. **CLI-first, one-line first** — the most common actions complete in a single slash command. We don't add extra switches (YAGNI).
4. **No automatic installation** — `check-deps.sh` only diagnoses and instructs. The user's machine is never modified silently.
5. **Reproducibility** — every workflow's state is persisted in `.claude/project.db` (SQLite). Restart, restore, and reset all work through the same commands.
6. **Observability** — `project-view` is a debugging and demo tool that surfaces Claude Code hook events (prompt-submit / pre/post-tool-use / stop / idle) as a per-workspace chat timeline.
