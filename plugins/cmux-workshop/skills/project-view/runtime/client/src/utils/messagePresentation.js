/**
 * Message presentation helpers.
 *
 * Contract:
 * - Server (lib/parser.js) already normalizes { chatRole, displayStyle, promoted fields }.
 * - Client MUST trust server values. Only fall back to msg.parsed when a field is absent (v1 legacy).
 * - Do not invent new presentation rules here — mirror parser.js::deriveUIHints and
 *   parser.js::extractPromotedFromRaw as closely as possible.
 *
 * TODO(manual-regression): Verify the v1/v2 matrix for prompt-submit, stop, idle,
 * pre-tool-use, session-start, active, session-end, and notification/notify across
 * the user, assistant, tool, and system/alert rendering paths.
 */

function deriveUiHints(subcommand) {
  switch (subcommand) {
    case "prompt-submit":
      return { chatRole: "user", displayStyle: "bubble" };
    case "stop":
    case "idle":
      return { chatRole: "assistant", displayStyle: "bubble" };
    case "pre-tool-use":
      return { chatRole: "tool", displayStyle: "compact" };
    case "session-start":
    case "active":
    case "session-end":
      return { chatRole: "system", displayStyle: "badge" };
    case "notification":
    case "notify":
      return { chatRole: "alert", displayStyle: "alert" };
    default:
      return { chatRole: "system", displayStyle: "badge" };
  }
}

export function pickDisplayStyle(msg) {
  return msg.displayStyle || deriveUiHints(msg.subcommand).displayStyle;
}

export function pickChatRole(msg) {
  return msg.chatRole || deriveUiHints(msg.subcommand).chatRole;
}

export function pickPrompt(msg) {
  return msg.prompt_preview || msg.parsed?.prompt || "";
}

export function pickResponse(msg) {
  return (
    msg.response_preview ||
    msg.parsed?.last_assistant_message ||
    msg.parsed?.lastAssistantMessage ||
    ""
  );
}

export function pickToolSummary(msg) {
  if (msg.tool_summary) return msg.tool_summary;

  const input = msg.parsed?.tool_input;
  if (input && typeof input === "object") {
    const summary =
      input.file_path || input.command || input.pattern || input.query || input.description || "";
    return String(summary).substring(0, 120);
  }

  return "";
}

export function pickToolName(msg) {
  return msg.tool_name || msg.parsed?.tool_name || "";
}

function getToolInput(msg) {
  if (msg.tool_input) {
    if (typeof msg.tool_input === "object") return msg.tool_input;
    try {
      return JSON.parse(msg.tool_input);
    } catch {
      return null;
    }
  }
  if (msg.parsed?.tool_input && typeof msg.parsed.tool_input === "object") {
    return msg.parsed.tool_input;
  }
  return null;
}

function clip(value, max = 200) {
  if (value == null) return "";
  const str = typeof value === "string" ? value : String(value);
  return str.length > max ? str.slice(0, max) + "…" : str;
}

/**
 * tool_name별로 UI에 표시할 3-slot view를 반환한다.
 *   - primary:   inline head 의 1차 텍스트 (짧게)
 *   - secondary: inline head 의 2차 텍스트 (작은 톤)
 *   - code:      code block (pre-wrap, scrollable). 길면 여러 줄.
 * 없는 slot은 비워둔다.
 */
export function pickToolInputView(msg) {
  const name = pickToolName(msg);
  const input = getToolInput(msg);
  if (!input) return { primary: "", secondary: "", code: "" };

  switch (name) {
    case "Bash":
      return {
        primary: clip(input.description, 160),
        secondary: input.run_in_background ? "bg" : "",
        code: "",
      };
    case "TaskCreate":
      return {
        primary: clip(input.subject, 120),
        secondary: clip(input.description, 180),
        code: "",
      };
    case "TaskUpdate": {
      const head = [input.taskId ? `#${input.taskId}` : "", input.status].filter(Boolean).join(" → ");
      return {
        primary: head,
        secondary: clip(input.subject || input.description, 160),
        code: "",
      };
    }
    case "Read": {
      const range =
        input.offset != null
          ? `lines ${input.offset}${input.limit ? `–${Number(input.offset) + Number(input.limit)}` : "+"}`
          : "";
      return { primary: clip(input.file_path, 200), secondary: range, code: "" };
    }
    case "Edit":
    case "MultiEdit": {
      const tag = input.replace_all ? "replace_all" : "";
      return { primary: clip(input.file_path, 200), secondary: tag, code: "" };
    }
    case "Write":
      return {
        primary: clip(input.file_path, 200),
        secondary: "",
        code: typeof input.content === "string" ? clip(input.content, 4096) : "",
      };
    case "Grep":
    case "Glob":
      return {
        primary: clip(input.pattern, 140),
        secondary: clip(input.path || input.glob || input.type, 160),
        code: "",
      };
    case "Skill":
      return { primary: input.skill || "", secondary: clip(input.args, 160), code: "" };
    case "ScheduleWakeup":
      return {
        primary: input.delaySeconds != null ? `${input.delaySeconds}s` : "",
        secondary: clip(input.reason, 200),
        code: typeof input.prompt === "string" ? clip(input.prompt, 4096) : "",
      };
    case "ToolSearch":
      return { primary: clip(input.query, 160), secondary: "", code: "" };
    case "WebFetch":
    case "WebSearch":
      return {
        primary: clip(input.url || input.query, 200),
        secondary: "",
        code: typeof input.prompt === "string" ? clip(input.prompt, 4096) : "",
      };
    default: {
      // Fallback: 첫 번째 string 값을 primary로
      const entries = Object.entries(input).filter(([, v]) => v != null && v !== "");
      const firstStr = entries.find(([, v]) => typeof v === "string");
      return {
        primary: firstStr ? clip(firstStr[1], 200) : "",
        secondary: "",
        code: "",
      };
    }
  }
}

export function pickNotify(msg) {
  return {
    type: msg.notify_type || msg.parsed?.type || msg.parsed?.notification_type || "Attention",
    message: msg.notify_message || msg.parsed?.message || msg.parsed?.body || msg.parsed?.text || "",
  };
}

export function pickStopReason(msg) {
  return msg.stop_reason || msg.parsed?.reason || "";
}

export function pickSystemInfo(msg) {
  return {
    model: msg.model || msg.parsed?.model || "",
    source: msg.source || msg.parsed?.source || "",
    endReason: msg.end_reason || msg.parsed?.reason || "",
  };
}
