#!/usr/bin/env python3
"""cmux 소켓 프록시 실시간 트래픽 모니터 — Redis Stream 기반."""

import argparse
import asyncio
import collections
import json
import sys
import time

import redis.asyncio as aioredis

# ---------------------------------------------------------------------------
# ANSI 색상
# ---------------------------------------------------------------------------

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[36m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
WHITE = "\033[37m"
GRAY = "\033[90m"

# ---------------------------------------------------------------------------
# 스트림 키
# ---------------------------------------------------------------------------

STREAM_REQUESTS = "cmux:requests"
STREAM_RESPONSES = "cmux:responses"


# ---------------------------------------------------------------------------
# 유틸리티
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="cmux 소켓 트래픽 실시간 모니터",
    )
    parser.add_argument(
        "--history",
        type=int,
        default=0,
        metavar="N",
        help="최근 N건의 히스토리를 먼저 표시한 후 실시간 모니터링",
    )
    parser.add_argument(
        "--method",
        type=str,
        default=None,
        metavar="PATTERN",
        help="method 필드에 대한 대소문자 무시 부분 문자열 필터",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="각 엔트리를 JSON 라인으로 출력 (색상 없음)",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="스트림 통계만 표시하고 종료",
    )
    parser.add_argument(
        "--redis-url",
        type=str,
        default="redis://localhost:6379/0",
        help="Redis 연결 URL (기본값: redis://localhost:6379/0)",
    )
    return parser.parse_args()


def ts_to_display(ts_ms: str) -> str:
    """밀리초 타임스탬프 문자열을 HH:MM:SS.mmm 형식으로 변환."""
    try:
        t = int(ts_ms) / 1000.0
    except (ValueError, TypeError):
        return ts_ms
    local = time.localtime(t)
    millis = int(t * 1000) % 1000
    return time.strftime("%H:%M:%S", local) + f".{millis:03d}"


def format_size(size_str: str) -> str:
    """바이트 수를 읽기 좋은 형식으로 변환."""
    try:
        n = int(size_str)
    except (ValueError, TypeError):
        return size_str
    if n < 1024:
        return f"{n}B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f}KB"
    return f"{n / (1024 * 1024):.1f}MB"


def truncate(s: str, maxlen: int = 120) -> str:
    if len(s) <= maxlen:
        return s
    return s[:maxlen] + "..."


def matches_method(method: str, pattern: str | None) -> bool:
    """method가 pattern에 매치되는지 확인 (대소문자 무시, 부분 문자열)."""
    if pattern is None:
        return True
    return pattern.lower() in method.lower()


def decode_entry(raw: dict[bytes | str, bytes | str]) -> dict[str, str]:
    """Redis에서 읽은 엔트리의 키/값을 문자열로 디코딩."""
    result: dict[str, str] = {}
    for k, v in raw.items():
        key = k.decode("utf-8") if isinstance(k, bytes) else k
        val = v.decode("utf-8") if isinstance(v, bytes) else v
        result[key] = val
    return result


# ---------------------------------------------------------------------------
# 출력 포매팅
# ---------------------------------------------------------------------------


def format_text_line(entry: dict[str, str], stream_id: str) -> str:
    """텍스트 모드에서 한 줄 포맷 생성."""
    direction = entry.get("direction", "")
    method = entry.get("method", "")
    conn_id = entry.get("conn_id", "")[:8]
    ts_display = ts_to_display(entry.get("ts", ""))
    size_display = format_size(entry.get("size", "0"))
    data_preview = truncate(entry.get("data", ""))

    if direction == "request":
        prefix = f"{CYAN}{BOLD}\u2192 REQ{RESET}"
        method_color = CYAN
    else:
        ok = entry.get("ok", "")
        if ok == "true":
            prefix = f"{GREEN}{BOLD}\u2190 RES \u2713{RESET}"
            method_color = GREEN
        else:
            prefix = f"{RED}{BOLD}\u2190 RES \u2717{RESET}"
            method_color = RED

    parts = [
        f"{GRAY}{ts_display}{RESET}",
        prefix,
        f"{DIM}[{conn_id}]{RESET}",
        f"{method_color}{method}{RESET}",
        f"{DIM}({size_display}){RESET}",
        f"{GRAY}{data_preview}{RESET}",
    ]
    return " ".join(parts)


def format_json_line(entry: dict[str, str], stream_id: str) -> str:
    """JSON 모드에서 한 줄 포맷 생성."""
    obj = {
        "stream_id": stream_id,
        "conn_id": entry.get("conn_id", ""),
        "ts": entry.get("ts", ""),
        "direction": entry.get("direction", ""),
        "method": entry.get("method", ""),
        "data": entry.get("data", ""),
    }
    return json.dumps(obj, ensure_ascii=False)


def print_entry(
    entry: dict[str, str],
    stream_id: str,
    *,
    json_output: bool,
    method_filter: str | None,
) -> None:
    """필터를 적용하고 엔트리를 출력."""
    method = entry.get("method", "")
    if not matches_method(method, method_filter):
        return

    if json_output:
        line = format_json_line(entry, stream_id)
    else:
        line = format_text_line(entry, stream_id)

    print(line, flush=True)


# ---------------------------------------------------------------------------
# 통계 모드
# ---------------------------------------------------------------------------


async def show_stats(r: aioredis.Redis) -> None:
    """스트림 통계를 표시하고 종료."""
    print(f"\n{BOLD}=== cmux Stream 통계 ==={RESET}\n")

    for stream_key in (STREAM_REQUESTS, STREAM_RESPONSES):
        length = await r.xlen(stream_key)

        try:
            info = await r.xinfo_stream(stream_key)
            first_id = info.get("first-entry")
            last_id = info.get("last-entry")
            if first_id:
                first_id = first_id[0] if isinstance(first_id, (list, tuple)) else first_id
            if last_id:
                last_id = last_id[0] if isinstance(last_id, (list, tuple)) else last_id
        except Exception:
            first_id = None
            last_id = None

        label = "요청" if stream_key == STREAM_REQUESTS else "응답"
        print(f"  {CYAN}{label}{RESET} ({stream_key})")
        print(f"    길이: {BOLD}{length}{RESET}")
        if first_id:
            print(f"    첫 엔트리 ID: {first_id}")
        if last_id:
            print(f"    마지막 엔트리 ID: {last_id}")
        print()

    # 최근 1분 메서드 카운트
    print(f"  {YELLOW}최근 1분 메서드 통계:{RESET}\n")

    now_ms = int(time.time() * 1000)
    one_min_ago_ms = now_ms - 60_000
    start_id = f"{one_min_ago_ms}-0"

    counter: collections.Counter[str] = collections.Counter()

    for stream_key in (STREAM_REQUESTS, STREAM_RESPONSES):
        entries = await r.xrange(stream_key, min=start_id)
        for _entry_id, raw_fields in entries:
            fields = decode_entry(raw_fields)
            method = fields.get("method", "(unknown)")
            direction = fields.get("direction", "?")
            counter[f"{direction}:{method}"] += 1

    if counter:
        # 빈도순 정렬
        for key, count in counter.most_common(30):
            direction, method = key.split(":", 1)
            arrow = f"{CYAN}\u2192{RESET}" if direction == "request" else f"{GREEN}\u2190{RESET}"
            print(f"    {arrow} {method:<40s} {BOLD}{count}{RESET}")
    else:
        print(f"    {DIM}(최근 1분간 엔트리 없음){RESET}")

    print()


# ---------------------------------------------------------------------------
# 히스토리 표시
# ---------------------------------------------------------------------------


async def show_history(
    r: aioredis.Redis,
    count: int,
    *,
    json_output: bool,
    method_filter: str | None,
) -> dict[str, str]:
    """최근 N건의 히스토리를 시간순으로 표시.

    반환: 각 스트림에서 마지막으로 표시한 ID의 딕셔너리 (이후 실시간 모니터링 시작점).
    """
    merged: list[tuple[str, str, dict[str, str]]] = []
    last_ids: dict[str, str] = {}

    for stream_key in (STREAM_REQUESTS, STREAM_RESPONSES):
        entries = await r.xrevrange(stream_key, count=count)
        for entry_id, raw_fields in entries:
            eid = entry_id.decode("utf-8") if isinstance(entry_id, bytes) else entry_id
            fields = decode_entry(raw_fields)
            merged.append((eid, stream_key, fields))
            # xrevrange는 역순이므로 첫 번째가 가장 최신
            if stream_key not in last_ids:
                last_ids[stream_key] = eid

    # ts 기준으로 오름차순 정렬
    def sort_key(item: tuple[str, str, dict[str, str]]) -> float:
        try:
            return float(item[2].get("ts", "0"))
        except (ValueError, TypeError):
            return 0.0

    merged.sort(key=sort_key)

    if not json_output and merged:
        print(f"\n{DIM}--- 히스토리 (최근 {count}건) ---{RESET}\n")

    for entry_id, _stream_key, fields in merged:
        print_entry(fields, entry_id, json_output=json_output, method_filter=method_filter)

    if not json_output and merged:
        print(f"\n{DIM}--- 실시간 모니터링 시작 ---{RESET}\n")

    return last_ids


# ---------------------------------------------------------------------------
# 실시간 모니터링
# ---------------------------------------------------------------------------


async def monitor_realtime(
    r: aioredis.Redis,
    *,
    json_output: bool,
    method_filter: str | None,
    start_ids: dict[str, str] | None = None,
) -> None:
    """XREAD BLOCK으로 실시간 엔트리를 수신하여 표시."""
    # 각 스트림의 시작 ID 설정
    # "$"는 현재 이후의 새 엔트리만 읽음
    streams: dict[str, str] = {}
    for key in (STREAM_REQUESTS, STREAM_RESPONSES):
        if start_ids and key in start_ids:
            streams[key] = start_ids[key]
        else:
            streams[key] = "$"

    while True:
        try:
            result = await r.xread(streams, block=1000, count=100)
        except asyncio.CancelledError:
            return

        if not result:
            continue

        for stream_key_raw, entries in result:
            stream_key = (
                stream_key_raw.decode("utf-8")
                if isinstance(stream_key_raw, bytes)
                else stream_key_raw
            )

            for entry_id_raw, raw_fields in entries:
                entry_id = (
                    entry_id_raw.decode("utf-8")
                    if isinstance(entry_id_raw, bytes)
                    else entry_id_raw
                )
                fields = decode_entry(raw_fields)
                print_entry(
                    fields,
                    entry_id,
                    json_output=json_output,
                    method_filter=method_filter,
                )
                # 다음 XREAD를 위해 마지막 ID 갱신
                streams[stream_key] = entry_id


# ---------------------------------------------------------------------------
# 메인
# ---------------------------------------------------------------------------


async def run(args: argparse.Namespace) -> None:
    r = aioredis.from_url(args.redis_url, decode_responses=False)

    try:
        await r.ping()
    except Exception as e:
        print(f"{RED}Redis 연결 실패: {e}{RESET}", file=sys.stderr)
        await r.aclose()
        sys.exit(1)

    try:
        # 통계 모드
        if args.stats:
            # 통계 모드에서는 decode_responses=True가 편리하므로 별도 연결
            r_text = aioredis.from_url(args.redis_url, decode_responses=True)
            try:
                await show_stats(r_text)
            finally:
                await r_text.aclose()
            return

        start_ids: dict[str, str] | None = None

        # 히스토리 모드
        if args.history > 0:
            start_ids = await show_history(
                r,
                args.history,
                json_output=args.json_output,
                method_filter=args.method,
            )

        # 실시간 모니터링
        if not args.json_output:
            if not args.history:
                filter_msg = ""
                if args.method:
                    filter_msg = f"  {DIM}필터: {args.method}{RESET}"
                print(
                    f"\n{BOLD}cmux 트래픽 모니터{RESET}  "
                    f"{DIM}(Ctrl+C로 종료){RESET}{filter_msg}\n"
                )

        await monitor_realtime(
            r,
            json_output=args.json_output,
            method_filter=args.method,
            start_ids=start_ids,
        )

    finally:
        await r.aclose()


def main() -> None:
    args = parse_args()

    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        # Ctrl+C — 깔끔하게 종료
        if not args.json_output:
            print(f"\n{DIM}모니터 종료.{RESET}")


if __name__ == "__main__":
    main()
