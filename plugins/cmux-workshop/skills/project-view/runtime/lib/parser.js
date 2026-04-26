/**
 * Redis Stream flat field array를 객체로 변환
 * [key, value, key, value, ...] → { key: value, ... }
 */
function parseStreamEntry(fields) {
  const obj = {};
  for (let i = 0; i < fields.length; i += 2) {
    obj[fields[i]] = fields[i + 1];
  }
  return obj;
}

/**
 * raw_input JSON 문자열을 안전하게 파싱
 */
function parseRawInput(rawInputStr) {
  if (!rawInputStr) return {};
  try {
    return JSON.parse(rawInputStr);
  } catch {
    return { _raw: rawInputStr };
  }
}

/**
 * subcommand → UI 렌더링 힌트 매핑
 */
function deriveUIHints(subcommand) {
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

/**
 * v1 raw_input에서 promoted 필드를 추출 (하위 호환)
 */
function extractPromotedFromRaw(parsed, subcommand) {
  const promoted = {};
  switch (subcommand) {
    case "session-start":
    case "active":
      if (parsed.model) promoted.model = String(parsed.model).substring(0, 40);
      if (parsed.source) promoted.source = String(parsed.source).substring(0, 20);
      break;
    case "prompt-submit":
      if (parsed.prompt) promoted.prompt_preview = String(parsed.prompt).substring(0, 200);
      break;
    case "pre-tool-use":
      if (parsed.tool_name) promoted.tool_name = String(parsed.tool_name).substring(0, 60);
      if (parsed.tool_input && typeof parsed.tool_input === "object") {
        const input = parsed.tool_input;
        const summary = input.file_path || input.command || input.pattern || input.query || input.description || "";
        promoted.tool_summary = String(summary).substring(0, 120);
        // v1 경로에서도 v2 enrich와 동일한 contract로 tool_input JSON 제공
        try {
          promoted.tool_input = JSON.stringify(input).slice(0, 4096);
        } catch {
          /* circular/non-serializable → skip */
        }
      }
      break;
    case "stop":
    case "idle":
      if (parsed.last_assistant_message) {
        promoted.response_preview = String(parsed.last_assistant_message).substring(0, 200);
      } else if (parsed.lastAssistantMessage) {
        promoted.response_preview = String(parsed.lastAssistantMessage).substring(0, 200);
      }
      if (parsed.reason) promoted.stop_reason = String(parsed.reason).substring(0, 40);
      break;
    case "notification":
    case "notify":
      promoted.notify_type = parsed.type || parsed.notification_type || "Attention";
      const msg = parsed.message || parsed.body || parsed.text || "";
      promoted.notify_message = String(msg).substring(0, 200);
      break;
    case "session-end":
      promoted.end_reason = parsed.reason || "normal";
      break;
  }
  return promoted;
}

/**
 * Redis Stream 엔트리를 정규화된 ChatEvent 객체로 변환
 * v1/v2 스키마 모두 지원
 *
 * @param {string} id - Redis Stream entry ID
 * @param {string[]} fields - flat key-value array from XREAD
 * @returns {object} ChatEvent
 */
function normalizeMessage(id, fields) {
  const entry = parseStreamEntry(fields);
  const schemaVersion = parseInt(entry.schema_version || "1", 10);
  const subcommand = entry.subcommand || "unknown";
  const uiHints = deriveUIHints(subcommand);

  const event = {
    id,
    subcommand,
    workspace_id: entry.workspace_id || "",
    surface_id: entry.surface_id || "",
    session_id: entry.session_id || "",
    cwd: entry.cwd || "",
    timestamp: entry.timestamp || "",
    hostname: entry.hostname || "",
    schema_version: schemaVersion,
    ...uiHints,
  };

  if (schemaVersion >= 2) {
    // v2: promoted 필드 직접 사용, detail은 Hash 참조
    event.detail_ref = entry.detail_ref || null;
    event.detail_hash = entry.detail_hash || null;

    // promoted fields
    if (entry.model) event.model = entry.model;
    if (entry.source) event.source = entry.source;
    if (entry.prompt_preview) event.prompt_preview = entry.prompt_preview;
    if (entry.tool_name) event.tool_name = entry.tool_name;
    if (entry.tool_summary) event.tool_summary = entry.tool_summary;
    if (entry.tool_input) event.tool_input = entry.tool_input;
    if (entry.response_preview) event.response_preview = entry.response_preview;
    if (entry.stop_reason) event.stop_reason = entry.stop_reason;
    if (entry.notify_type) event.notify_type = entry.notify_type;
    if (entry.notify_message) event.notify_message = entry.notify_message;
    if (entry.end_reason) event.end_reason = entry.end_reason;
  } else {
    // v1: raw_input 인라인 파싱 후 promoted 필드 추출
    event.detail_ref = null;
    event.detail_hash = null;

    const parsed = parseRawInput(entry.raw_input);
    event.parsed = parsed; // v1 호환: 전체 parsed 객체 유지
    const promoted = extractPromotedFromRaw(parsed, subcommand);
    Object.assign(event, promoted);
  }

  return event;
}

module.exports = { parseStreamEntry, parseRawInput, normalizeMessage, deriveUIHints };
