#!/usr/bin/env python3
"""cmux Consumer Group 기반 Redis Stream 처리기.

proxy.py가 적재한 Redis Stream(cmux:requests, cmux:responses)을
Consumer Group(XREADGROUP)으로 소비하며, 플러그형 핸들러를 통해
로그 출력, 레이턴시 분석, 시간 윈도우 집계, 웹훅 전달 등을 수행한다.

사용법:
    python3 consumer.py                            # 기본(log) 핸들러
    python3 consumer.py --handler latency          # 레이턴시 분석
    python3 consumer.py --handler aggregation      # 시간 윈도우 집계
    python3 consumer.py --group analytics          # Consumer Group 지정
    python3 consumer.py --consumer worker-2        # Consumer 이름 지정
    python3 consumer.py --streams cmux:requests    # 특정 스트림만 구독
    python3 consumer.py --redis-url redis://host:6379/0
"""

import argparse
import asyncio
import collections
import logging
import statistics
import signal
import time
from abc import ABC, abstractmethod

import redis.asyncio as aioredis

logger = logging.getLogger("cmux-consumer")


# ---------------------------------------------------------------------------
# Handler Interface & Built-in Implementations
# ---------------------------------------------------------------------------


class BaseHandler(ABC):
    """핸들러 인터페이스. 모든 핸들러는 이 클래스를 상속한다."""

    @abstractmethod
    async def handle(self, stream_key: str, entry_id: str, fields: dict[str, str]) -> None:
        """개별 스트림 엔트리를 처리한다."""
        raise NotImplementedError

    async def flush(self) -> None:
        """주기적으로 호출되어 누적 결과를 출력한다 (기본 10초)."""
        pass

    async def close(self) -> None:
        """리소스 정리."""
        pass


class LogHandler(BaseHandler):
    """디버깅용 로그 핸들러. 모든 엔트리를 사람이 읽기 쉬운 형태로 출력한다."""

    async def handle(self, stream_key: str, entry_id: str, fields: dict[str, str]) -> None:
        direction = fields.get("direction", "?")
        method = fields.get("method", "")
        conn_id = fields.get("conn_id", "?")
        req_id = fields.get("req_id", "")
        size = fields.get("size", "")

        if direction == "request":
            arrow = ">>>"
            detail = method or "(no method)"
        else:
            arrow = "<<<"
            ok = fields.get("ok", "")
            result_keys = fields.get("result_keys", "")
            status = f"ok={ok}" if ok else ""
            keys_info = f" keys=[{result_keys}]" if result_keys else ""
            detail = f"{method or '(no method)'} {status}{keys_info}".strip()

        size_str = f" ({size}B)" if size else ""
        req_str = f" #{req_id}" if req_id else ""

        logger.info(
            "[%s] %s %s%s %s%s",
            stream_key.split(":")[-1],
            arrow,
            conn_id[:16],
            req_str,
            detail,
            size_str,
        )


class LatencyHandler(BaseHandler):
    """요청-응답 레이턴시를 측정하고 주기적으로 통계를 출력한다.

    요청이 들어오면 (conn_id, req_id)를 키로 (method, ts)를 저장하고,
    응답이 들어오면 매칭하여 레이턴시를 계산한다.
    flush 시 avg, p50, p99를 출력하고 버퍼를 초기화한다.
    """

    def __init__(self) -> None:
        # pending: "conn_id:req_id" -> (method, ts_ms)
        self._pending: dict[str, tuple[str, float]] = {}
        self._latencies: list[float] = []
        self._matched_count: int = 0
        self._orphan_responses: int = 0

    async def handle(self, stream_key: str, entry_id: str, fields: dict[str, str]) -> None:
        conn_id = fields.get("conn_id", "")
        req_id = fields.get("req_id", "")
        ts = fields.get("ts", "")
        direction = fields.get("direction", "")
        method = fields.get("method", "")

        if not req_id or not ts:
            return

        key = f"{conn_id}:{req_id}"

        if direction == "request":
            self._pending[key] = (method, float(ts))
        elif direction == "response":
            if key in self._pending:
                req_method, req_ts = self._pending.pop(key)
                latency_ms = float(ts) - req_ts
                if latency_ms >= 0:
                    self._latencies.append(latency_ms)
                    self._matched_count += 1
            else:
                self._orphan_responses += 1

    async def flush(self) -> None:
        if not self._latencies:
            pending_count = len(self._pending)
            if pending_count > 0:
                logger.info("[latency] 대기중 요청 %d건, 측정된 레이턴시 없음", pending_count)
            return

        avg = statistics.mean(self._latencies)
        p50 = statistics.median(self._latencies)
        sorted_lat = sorted(self._latencies)
        p99_idx = max(0, int(len(sorted_lat) * 0.99) - 1)
        p99 = sorted_lat[p99_idx]

        logger.info(
            "[latency] samples=%d  avg=%.1fms  p50=%.1fms  p99=%.1fms  "
            "matched=%d  pending=%d  orphans=%d",
            len(self._latencies),
            avg,
            p50,
            p99,
            self._matched_count,
            len(self._pending),
            self._orphan_responses,
        )

        self._latencies.clear()
        self._matched_count = 0
        self._orphan_responses = 0

    async def close(self) -> None:
        await self.flush()
        self._pending.clear()


class AggregationHandler(BaseHandler):
    """1분 윈도우 기반 메서드 호출 집계 및 에러율 추적.

    flush마다 현재 윈도우의 메서드별 호출 수와 에러율을 출력한다.
    """

    def __init__(self) -> None:
        self._method_counts: collections.Counter[str] = collections.Counter()
        self._total_responses: int = 0
        self._error_responses: int = 0
        self._total_requests: int = 0
        self._window_start: float = time.time()

    async def handle(self, stream_key: str, entry_id: str, fields: dict[str, str]) -> None:
        direction = fields.get("direction", "")
        method = fields.get("method", "")

        if direction == "request":
            self._total_requests += 1
            if method:
                self._method_counts[method] += 1
        elif direction == "response":
            self._total_responses += 1
            ok = fields.get("ok", "")
            if ok == "false":
                self._error_responses += 1

    async def flush(self) -> None:
        now = time.time()
        window_sec = now - self._window_start
        total_events = self._total_requests + self._total_responses

        if total_events == 0:
            return

        error_rate = (
            (self._error_responses / self._total_responses * 100)
            if self._total_responses > 0
            else 0.0
        )

        # 메서드별 호출 수를 내림차순 정렬
        top_methods = self._method_counts.most_common(15)
        methods_str = "  ".join(f"{m}={c}" for m, c in top_methods)

        logger.info(
            "[aggregation] window=%.0fs  requests=%d  responses=%d  "
            "errors=%d (%.1f%%)  methods: %s",
            window_sec,
            self._total_requests,
            self._total_responses,
            self._error_responses,
            error_rate,
            methods_str or "(none)",
        )

        # 윈도우 리셋
        self._method_counts.clear()
        self._total_responses = 0
        self._error_responses = 0
        self._total_requests = 0
        self._window_start = now

    async def close(self) -> None:
        await self.flush()


class WebhookHandler(BaseHandler):
    """웹훅 전달 스텁. 지정된 메서드의 요청만 필터링하여 전달 대상을 로그로 출력한다.

    실제 HTTP POST는 수행하지 않으며, 트리거 조건 충족 시 어떤 데이터가
    전송될지 로그로 기록한다.
    """

    def __init__(self, webhook_url: str, trigger_methods: list[str]) -> None:
        self._webhook_url = webhook_url
        self._trigger_methods = trigger_methods
        self._trigger_count: int = 0

    async def handle(self, stream_key: str, entry_id: str, fields: dict[str, str]) -> None:
        direction = fields.get("direction", "")
        if direction != "request":
            return

        method = fields.get("method", "")
        if method not in self._trigger_methods:
            return

        self._trigger_count += 1
        logger.info(
            "[webhook] WOULD POST to %s  method=%s  conn_id=%s  req_id=%s  size=%s",
            self._webhook_url,
            method,
            fields.get("conn_id", "?"),
            fields.get("req_id", "?"),
            fields.get("size", "?"),
        )

    async def flush(self) -> None:
        if self._trigger_count > 0:
            logger.info(
                "[webhook] 트리거 누적 %d건 → %s",
                self._trigger_count,
                self._webhook_url,
            )
            self._trigger_count = 0

    async def close(self) -> None:
        await self.flush()


# ---------------------------------------------------------------------------
# Handler Registry
# ---------------------------------------------------------------------------

HANDLER_REGISTRY: dict[str, type[BaseHandler]] = {
    "log": LogHandler,
    "latency": LatencyHandler,
    "aggregation": AggregationHandler,
}


def create_handler(name: str) -> BaseHandler:
    """이름으로 핸들러 인스턴스를 생성한다."""
    cls = HANDLER_REGISTRY.get(name)
    if cls is None:
        available = ", ".join(sorted(HANDLER_REGISTRY.keys()))
        raise ValueError(f"알 수 없는 핸들러: {name!r} (사용 가능: {available})")
    return cls()


# ---------------------------------------------------------------------------
# Stream Consumer
# ---------------------------------------------------------------------------

DEFAULT_STREAMS = ["cmux:requests", "cmux:responses"]
FLUSH_INTERVAL = 10.0
BLOCK_MS = 2000
READ_COUNT = 10


class StreamConsumer:
    """Consumer Group 기반 Redis Stream 소비자.

    XREADGROUP으로 엔트리를 읽고, 핸들러 처리 후 XACK로 확인 응답한다.
    flush 루프를 별도 태스크로 돌려 주기적으로 핸들러의 flush를 호출한다.
    """

    def __init__(
        self,
        redis_client: aioredis.Redis,
        group: str,
        consumer_name: str,
        handler: BaseHandler,
        streams: list[str],
    ) -> None:
        self._redis = redis_client
        self._group = group
        self._consumer = consumer_name
        self._handler = handler
        self._streams = streams
        self._running = False

    async def _ensure_groups(self) -> None:
        """각 스트림에 대해 Consumer Group을 생성한다. 이미 존재하면 무시."""
        for stream in self._streams:
            try:
                await self._redis.xgroup_create(
                    name=stream,
                    groupname=self._group,
                    id="0",
                    mkstream=True,
                )
                logger.info("Consumer Group 생성: stream=%s group=%s", stream, self._group)
            except aioredis.ResponseError as e:
                if "BUSYGROUP" in str(e):
                    logger.debug("Consumer Group 이미 존재: stream=%s group=%s", stream, self._group)
                else:
                    raise

    async def _consume_loop(self) -> None:
        """XREADGROUP 루프. 엔트리를 읽고 핸들러에 전달 후 XACK한다."""
        stream_map = {s: ">" for s in self._streams}

        while self._running:
            try:
                results = await self._redis.xreadgroup(
                    groupname=self._group,
                    consumername=self._consumer,
                    streams=stream_map,
                    count=READ_COUNT,
                    block=BLOCK_MS,
                )
            except asyncio.CancelledError:
                raise
            except aioredis.ConnectionError as e:
                logger.warning("Redis 연결 오류, 재시도 (1초 후): %s", e)
                await asyncio.sleep(1.0)
                continue
            except Exception as e:
                logger.error("XREADGROUP 오류: %s", e, exc_info=True)
                await asyncio.sleep(1.0)
                continue

            if not results:
                continue

            for stream_key, entries in results:
                # redis.asyncio returns stream_key as str when decode_responses=True
                if isinstance(stream_key, bytes):
                    stream_key = stream_key.decode()

                for entry_id, fields in entries:
                    if isinstance(entry_id, bytes):
                        entry_id = entry_id.decode()

                    # Decode bytes fields if needed
                    decoded: dict[str, str] = {}
                    for k, v in fields.items():
                        key = k.decode() if isinstance(k, bytes) else k
                        val = v.decode() if isinstance(v, bytes) else v
                        decoded[key] = val

                    try:
                        await self._handler.handle(stream_key, entry_id, decoded)
                    except Exception as e:
                        logger.error(
                            "핸들러 오류 (stream=%s entry=%s): %s",
                            stream_key,
                            entry_id,
                            e,
                            exc_info=True,
                        )

                    # XACK: 핸들러 성공 여부와 관계없이 ACK 처리
                    # (핸들러 예외 시에도 엔트리를 다시 읽지 않도록)
                    try:
                        await self._redis.xack(stream_key, self._group, entry_id)
                    except Exception as e:
                        logger.warning("XACK 실패 (stream=%s entry=%s): %s", stream_key, entry_id, e)

    async def _flush_loop(self) -> None:
        """주기적으로 핸들러의 flush를 호출한다."""
        while self._running:
            await asyncio.sleep(FLUSH_INTERVAL)
            try:
                await self._handler.flush()
            except Exception as e:
                logger.error("핸들러 flush 오류: %s", e, exc_info=True)

    async def run(self) -> None:
        """Consumer를 시작한다. Ctrl+C(SIGINT/SIGTERM)로 종료."""
        self._running = True
        await self._ensure_groups()

        logger.info(
            "Consumer 시작: group=%s consumer=%s streams=%s handler=%s",
            self._group,
            self._consumer,
            self._streams,
            type(self._handler).__name__,
        )

        stop_event = asyncio.Event()
        loop = asyncio.get_running_loop()

        def _signal_handler() -> None:
            logger.info("종료 시그널 수신, Consumer 중단 중...")
            self._running = False
            stop_event.set()

        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, _signal_handler)

        consume_task = asyncio.create_task(self._consume_loop())
        flush_task = asyncio.create_task(self._flush_loop())

        # stop_event가 설정될 때까지 대기
        await stop_event.wait()

        # 태스크 정리
        consume_task.cancel()
        flush_task.cancel()
        for task in (consume_task, flush_task):
            try:
                await task
            except asyncio.CancelledError:
                pass

        # 최종 flush 및 정리
        try:
            await self._handler.flush()
        except Exception as e:
            logger.error("최종 flush 오류: %s", e)

        try:
            await self._handler.close()
        except Exception as e:
            logger.error("핸들러 close 오류: %s", e)

        logger.info("Consumer 종료 완료")


# ---------------------------------------------------------------------------
# Convenience Function
# ---------------------------------------------------------------------------


async def run_consumer(
    redis_url: str,
    group: str,
    consumer_name: str,
    handler: BaseHandler,
    streams: list[str] | None = None,
) -> None:
    """편의 함수: Redis 연결 생성, StreamConsumer 실행, 정리까지 일괄 수행."""
    client = aioredis.from_url(redis_url, decode_responses=True)

    try:
        await client.ping()
        logger.info("Redis 연결 성공: %s", redis_url)
    except Exception as e:
        logger.error("Redis 연결 실패: %s", e)
        await client.aclose()
        raise

    consumer = StreamConsumer(
        redis_client=client,
        group=group,
        consumer_name=consumer_name,
        handler=handler,
        streams=streams or DEFAULT_STREAMS,
    )

    try:
        await consumer.run()
    finally:
        await client.aclose()
        logger.debug("Redis 연결 종료")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="cmux Consumer Group 기반 Redis Stream 처리기",
    )
    parser.add_argument(
        "--handler",
        default="log",
        choices=sorted(HANDLER_REGISTRY.keys()),
        help="사용할 핸들러 (기본: log)",
    )
    parser.add_argument(
        "--group",
        default="default-group",
        help="Consumer Group 이름 (기본: default-group)",
    )
    parser.add_argument(
        "--consumer",
        default="worker-1",
        help="Consumer 이름 (기본: worker-1)",
    )
    parser.add_argument(
        "--streams",
        nargs="+",
        default=None,
        help="구독할 스트림 키 (기본: cmux:requests cmux:responses)",
    )
    parser.add_argument(
        "--redis-url",
        default="redis://localhost:6379/0",
        help="Redis 연결 URL (기본: redis://localhost:6379/0)",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="로그 레벨 (기본: INFO)",
    )
    return parser.parse_args()


async def main() -> None:
    args = parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
    )

    handler = create_handler(args.handler)

    await run_consumer(
        redis_url=args.redis_url,
        group=args.group,
        consumer_name=args.consumer,
        handler=handler,
        streams=args.streams,
    )


if __name__ == "__main__":
    asyncio.run(main())
