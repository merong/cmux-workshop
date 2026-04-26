# CLAUDE.md — cmux-workshop maintenance notes

This is a **unified Claude Code plugin marketplace** that fuses two upstream
projects into one:

| Source | What was pulled in |
|---|---|
| `~/works/agent/cmux-monitor/` | vendored under `skills/project-view/runtime/` (Python proxy + Node web stack) |
| `~/works/agent/cmux-skills/merong-plugins/plugins/upstar/` | ported to `plugins/cmux-workshop/` (agents/commands/hooks/tools + 7 skills), with all `upstar` references renamed to `cmux-workshop` |

The headline feature is the `/project-view` slash command, which boots the
monitor stack and opens the dashboard in the default browser.

## Repo shape (DO NOT change without updating SKILL.md)

```
.claude-plugin/marketplace.json
.claude/settings.json                       ← enables this plugin locally
plugins/cmux-workshop/
    .claude-plugin/plugin.json
    agents/      <persona>.md               (orchestrator, implementer, reviewer,
                                             architect, debugger, researcher)
    AGENTS.md                                  standard hand-off/report spec
    commands/    project-*.md, code-quality.md, code-explore.md,
                 merge-permissions.md
    hooks/
        hooks.json                          PreToolUse(Bash) chain
        scripts/{block-dangerous,save-conv-before-commit}.sh
    tools/
        db.sh, schema.sql, SCHEMA.md, README.md
        queries/    *.sql                   reusable read queries
        scripts/    project-info-{capture,show}.sh
    skills/
        project-view/                       ← NEW skill (this plugin's headline)
            SKILL.md
            scripts/{start,stop,check-deps,helpers}.sh
            runtime/                        vendored cmux-monitor
            references/{architecture,troubleshooting}.md
        cmux/                               cmux CLI control
        save-conversation/
        project-{init,agent,reload,reset,status}/
```

Skills resolve plugin paths via `${CLAUDE_PLUGIN_ROOT}`. `helpers.sh` uses
`$(dirname "${BASH_SOURCE[0]}")/..` so the launcher works whether invoked
through Claude Code or directly from a shell.

## Naming convention

Two distinct identifiers — keep them straight:

- **Plugin** name (and namespace): `cmux-workshop`. Used in `marketplace.json`,
  `plugin.json`, env vars (`CMUX_WORKSHOP_DB_PATH`, `CMUX_WORKSHOP_DEBUG`),
  PID/log files (`/tmp/cmux-workshop-*.{pid,log}`), the script log prefix
  `[cmux-workshop]`, and the skill-call namespace
  (`cmux-workshop:save-conversation`, `cmux-workshop:project-view`).
- **Skill** names: follow the `project-*` family (`project-view`,
  `project-init`, `project-agent`, `project-reload`, `project-reset`,
  `project-status`) plus standalone `cmux` and `save-conversation`. The
  monitor launcher's slash command is therefore `/project-view`, not
  `/cmux-workshop`.

The legacy `upstar` / `upstar-plugins` names from the source repo were
swept across all copied files. If you re-vendor any upstream content, run
the rename pass at the bottom of this file.

## Where to make changes

| Want to change… | Edit |
|---|---|
| Monitor launcher behavior | `skills/project-view/scripts/start.sh` |
| Dependency checks / install hints | `skills/project-view/scripts/check-deps.sh` |
| Skill description / triggers | the relevant `skills/<name>/SKILL.md` frontmatter |
| Hook chain | `hooks/hooks.json` and `hooks/scripts/*.sh` |
| Slash commands | `commands/<name>.md` |
| SQLite schema or db wrapper | `tools/schema.sql`, `tools/db.sh` |
| Plugin version | both `marketplace.json` AND `plugins/cmux-workshop/.claude-plugin/plugin.json` (lockstep) |
| Vendored monitor code | DO NOT edit in place — re-vendor from `cmux-monitor` |

## Re-vendoring the monitor

The runtime is a snapshot of `~/works/agent/cmux-monitor` (excluding
`node_modules`, `dist`, `__pycache__`, `.claude/`, `.superpowers/`).

```bash
SRC=/Users/brian/works/agent/cmux-monitor
DST=/Users/brian/works/agent/cmux-workshop/plugins/cmux-workshop/skills/project-view/runtime

cp "$SRC"/{proxy.py,monitor.py,polling_monitor.py,consumer.py,cmux-proxy.sh,requirements.txt,README.md,SPEC.md,SPEC-Terminal-io.md} "$DST/"

rsync -a --delete \
  --exclude node_modules --exclude dist \
  "$SRC/web/" "$DST/web/"

chmod +x "$DST/cmux-proxy.sh"
```

After re-vendoring, run `scripts/check-deps.sh` to confirm structure (e.g.
`web/scripts/dev.js` not renamed, etc).

Keep `plugins/cmux-workshop/AGENTS.md` intact. It is not part of the vendored
monitor runtime; `project-agent` and `project-reload` copy it into user
projects as the standard hand-off/report contract.

## Re-syncing the upstar plugin pieces

```bash
SRC=/Users/brian/works/agent/cmux-skills/merong-plugins/plugins/upstar
DST=/Users/brian/works/agent/cmux-workshop/plugins/cmux-workshop

# overwrite copied trees (do NOT touch skills/project-view or .claude-plugin/)
rsync -a --delete "$SRC/agents/"   "$DST/agents/"
rsync -a --delete "$SRC/commands/" "$DST/commands/"
rsync -a --delete "$SRC/hooks/"    "$DST/hooks/"
rsync -a --delete "$SRC/tools/"    "$DST/tools/"
for d in cmux save-conversation project-init project-agent \
         project-reload project-reset project-status; do
  rsync -a --delete "$SRC/skills/$d/" "$DST/skills/$d/"
done

# preserve this repo's standard hand-off/report spec
test -f "$DST/AGENTS.md" || {
  echo "ERROR: $DST/AGENTS.md is missing; restore the cmux-workshop standard copy" >&2
  exit 1
}

# rename pass — the plugin name and env vars must match this repo
cd "$DST"
grep -rl 'upstar'                tools commands hooks skills agents \
  | xargs sed -i '' 's/upstar/cmux-workshop/g'
grep -rl 'UPSTAR_DB_PATH\|UPSTAR_DEBUG' tools commands hooks skills agents \
  | xargs sed -i '' -e 's/UPSTAR_DB_PATH/CMUX_WORKSHOP_DB_PATH/g' \
                    -e 's/UPSTAR_DEBUG/CMUX_WORKSHOP_DEBUG/g'
grep -rl 'Upstar Project Workflow' tools commands hooks skills agents \
  | xargs sed -i '' 's/Upstar Project Workflow/cmux-workshop Project Workflow/g'
```

Note: `skills/tdd-team` from the upstream `upstar` plugin is intentionally
**not** mirrored here. If you ever want it back, add it to the loop above.

Always finish with the verification commands below.

## Versioning rules

Bump in lockstep:

- `marketplace.json` → `plugins[0].version`
- `plugins/cmux-workshop/.claude-plugin/plugin.json` → `version`
- `skills/project-view/SKILL.md` → frontmatter `version`
- (Other skills bump their own SKILL.md `version` only when their behavior changes.)

## Out of scope (intentional)

- No `tdd-team` skill (dropped from the upstream port).
- No `/project-view-status`. Use `/project-view` to start and
  `/project-view-stop` to stop the monitor/proxy stack.
- No automatic install of Redis / Node / Python deps. `check-deps.sh`
  reports and exits non-zero only.
- No CI. Verification is the manual sequence below.

## Sanity check after any edit

```bash
# JSON manifests valid
for f in .claude-plugin/marketplace.json \
         plugins/cmux-workshop/.claude-plugin/plugin.json \
         plugins/cmux-workshop/hooks/hooks.json; do
  python3 -c "import json; json.load(open('$f'))" && echo "$f OK"
done

# bash syntax across every shell script
find plugins/cmux-workshop -name '*.sh' -not -path '*/runtime/*' \
  -exec bash -n {} \; -exec echo "syntax OK: {}" \;

# dependency probe
bash plugins/cmux-workshop/skills/project-view/scripts/check-deps.sh

# end-to-end (only if dependencies are installed)
bash plugins/cmux-workshop/skills/project-view/scripts/start.sh
# expect: "READY: http://localhost:5173" on stdout
```
