#!/usr/bin/env bash
# verify-pane-ready.sh — Check whether a cmux surface has reached a
# "ready for input" state after launching its CLI and (optionally)
# injecting a persona.
#
# Usage:
#   verify-pane-ready.sh --surface <ref> --cli <claude|codex|gemini|custom>
#                        [--retries N] [--interval SEC] [--min-lines N]
#
# Exit codes:
#   0  — ready (stdout: "READY <surface>")
#   1  — timed out (stdout: "NOT_READY <surface> timeout")
#   2  — error pattern detected (stdout: "ERROR <surface> <reason>")
#   3  — cmux or usage error (stderr)
#
# Strategy:
#   Poll `cmux read-screen --surface <ref> --lines 80` until one of:
#     - ready marker matched  → ready
#     - error marker matched  → error
#     - attempts exhausted    → timeout
#
# Detection is deliberately conservative: a pane is considered ready
# when it has populated content AND does not contain an error marker
# AND (optionally) shows a CLI-specific prompt cue. We err toward
# "not ready" rather than false positives — callers can retry or
# surface the warning.

set -uo pipefail

SURFACE=""
CLI=""
RETRIES=10
INTERVAL=1.0
MIN_LINES=3

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 3
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface)   SURFACE="$2"; shift 2 ;;
    --cli)       CLI="$2"; shift 2 ;;
    --retries)   RETRIES="$2"; shift 2 ;;
    --interval)  INTERVAL="$2"; shift 2 ;;
    --min-lines) MIN_LINES="$2"; shift 2 ;;
    --help|-h)   usage ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

[[ -n "$SURFACE" ]] || { echo "--surface required" >&2; exit 3; }
[[ -n "$CLI"     ]] || { echo "--cli required (claude|codex|gemini|custom)" >&2; exit 3; }
command -v cmux >/dev/null 2>&1 || { echo "cmux CLI not found" >&2; exit 3; }

# Patterns that indicate the pane crashed or is stuck at an error
# message rather than a ready prompt. Keep this list conservative —
# false error detection blocks legitimate ready states.
ERROR_PATTERNS=(
  'command not found'
  'No such file or directory'
  'permission denied'
  'authentication (required|failed)'
  'not logged in'
  'rate limit'
  'Error: '
  'FATAL'
  'Traceback \(most recent call last\)'
)

# CLI-specific ready cues. Matching ANY one of these (after the
# generic non-empty + no-error checks) confirms the REPL is live.
# Patterns are grep -E (extended regex) friendly.
case "$CLI" in
  claude)
    READY_PATTERNS=(
      '╭─'                     # welcome/prompt box top border
      '│ >'                    # Claude Code prompt cursor in bordered box
      '? for shortcuts'        # footer shortcut hint
      'Welcome to Claude Code'
    )
    ;;
  codex)
    READY_PATTERNS=(
      'user@'                  # codex REPL user prompt marker
      '>>> '                   # interactive prompt
      'codex>'
      'Type your message'
      'Ready'
    )
    ;;
  gemini)
    READY_PATTERNS=(
      'gemini>'
      '>>> '
      'Type a message'
      'Gemini'
    )
    ;;
  custom|*)
    READY_PATTERNS=(
      '\$ '                    # bash/zsh prompt
      '% '
      '> '
    )
    ;;
esac

# ---- helpers ----

read_screen() {
  cmux read-screen --surface "$SURFACE" --lines 80 2>/dev/null || return 1
}

matches_any() {
  local text="$1"; shift
  for pat in "$@"; do
    if echo "$text" | grep -Eq -- "$pat"; then
      return 0
    fi
  done
  return 1
}

# ---- main poll loop ----

attempt=0
last_screen=""

while (( attempt < RETRIES )); do
  attempt=$(( attempt + 1 ))

  screen="$(read_screen)" || {
    echo "NOT_READY $SURFACE cmux_read_failed" >&2
    sleep "$INTERVAL"
    continue
  }
  last_screen="$screen"

  # Collapse to non-empty content lines for min-lines check
  non_empty=$(echo "$screen" | awk 'NF > 0' | wc -l | tr -d ' ')

  # 1) Check for error patterns FIRST — they take precedence
  if matches_any "$screen" "${ERROR_PATTERNS[@]}"; then
    # Extract the first matching line for a helpful reason
    reason=$(echo "$screen" | grep -Ei "$(IFS='|'; echo "${ERROR_PATTERNS[*]}")" | head -1 | tr -d '\r' | cut -c1-120)
    echo "ERROR $SURFACE ${reason:-error_pattern_matched}"
    exit 2
  fi

  # 2) Require minimum populated content
  if (( non_empty < MIN_LINES )); then
    sleep "$INTERVAL"
    continue
  fi

  # 3) Check for CLI-specific ready cues
  if matches_any "$screen" "${READY_PATTERNS[@]}"; then
    echo "READY $SURFACE"
    exit 0
  fi

  sleep "$INTERVAL"
done

# Fallback: if we have content but never matched a ready cue, emit
# a timeout result so the caller can decide whether to warn or retry.
echo "NOT_READY $SURFACE timeout_after_${RETRIES}x${INTERVAL}s"
exit 1
