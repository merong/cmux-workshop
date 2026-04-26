#!/bin/bash
command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')
[ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(pwd)

TOKENS_JSON=$(python3 -c 'import json,shlex,sys; print(json.dumps(shlex.split(sys.stdin.read())))' <<< "$COMMAND")

python3 - "$TOKENS_JSON" "$PROJECT_DIR" <<'PY'
import json
import os
import shlex
import sys

tokens = json.loads(sys.argv[1])
project_dir = os.path.normpath(os.path.abspath(sys.argv[2]))


def is_rm(token):
    return token == "rm" or token.endswith("/rm")


def is_shell(token):
    base = os.path.basename(token)
    return base in {"bash", "sh", "zsh"}


def is_git(token):
    return token == "git" or token.endswith("/git")


def normalize_target(target):
    if os.path.isabs(target):
        return os.path.normpath(target)
    return os.path.normpath(os.path.join(project_dir, target))


def under_project(path):
    return path == project_dir or path.startswith(project_dir + os.sep)


def split_nested(command):
    try:
        return shlex.split(command)
    except ValueError:
        return []


def check_rm(argv):
    i = 0
    while i < len(argv):
        token = argv[i]

        if is_shell(token) and i + 2 < len(argv) and argv[i + 1] == "-c":
            nested = check_rm(split_nested(argv[i + 2]))
            if nested:
                return "BLOCKED: Indirect rm -rf via shell -c is not allowed"

        if token == "eval" and i + 1 < len(argv):
            nested = check_rm(split_nested(" ".join(argv[i + 1 :])))
            if nested:
                return "BLOCKED: Indirect rm -rf via eval is not allowed"

        if not is_rm(token):
            i += 1
            continue

        recursive = False
        targets = []
        j = i + 1
        parse_options = True
        while j < len(argv):
            arg = argv[j]
            if arg in {"&&", "||", ";", "|"}:
                break
            if parse_options and arg == "--":
                parse_options = False
                j += 1
                continue
            if parse_options and arg.startswith("-") and arg != "-":
                if "r" in arg or "R" in arg:
                    recursive = True
                j += 1
                continue
            targets.append(arg)
            j += 1

        if recursive:
            for target in targets:
                abs_path = normalize_target(target)
                if not under_project(abs_path):
                    return f"BLOCKED: rm -rf outside project directory ({abs_path} not under {project_dir})"

        i = max(j, i + 1)

    return None


def split_commands(argv):
    command = []
    for token in argv:
        if token in {"&&", "||", ";", "|"}:
            if command:
                yield command
                command = []
        else:
            command.append(token)
    if command:
        yield command


def check_force_push(argv):
    for command in split_commands(argv):
        if len(command) < 3 or not is_git(command[0]) or command[1] != "push":
            continue

        force = False
        branches = []
        end_options = False
        for arg in command[2:]:
            if arg == "--":
                end_options = True
                continue
            if not end_options and arg in {"--force", "--force-with-lease", "--force-if-includes"}:
                force = True
                continue
            if not end_options and arg.startswith("-") and "f" in arg:
                force = True
                continue
            branches.append(arg)

        if not force:
            continue

        for branch in branches:
            branch_name = branch.split(":", 1)[-1]
            if branch_name in {"main", "master"} or branch_name.startswith("refs/heads/main") or branch_name.startswith("refs/heads/master"):
                return "BLOCKED: force-push to main/master is not allowed"

    return None


message = check_rm(tokens) or check_force_push(tokens)
if message:
    print(message, file=sys.stderr)
    sys.exit(2)
PY

exit 0
