#!/usr/bin/env python3
"""cmux Socket Proxy — Redis Stream 트래픽 캡처 프록시 서버."""

import argparse
import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass, field

import redis.asyncio as aioredis

logger = logging.getLogger("cmux-proxy")


def detect_socket_path() -> str:
    """cmux identify --json으로 소켓 경로를 동적 감지."""
    try:
        result = subprocess.run(
            ["cmux", "identify", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        data = json.loads(result.stdout)
        return data["socket_path"]
    except Exception as e:
        logger.warning("cmux identify 실패, 기본 경로 사용: %s", e)
        return "/tmp/cmux.sock"


@dataclass
class ProxyConfig:
    listen_path: str = ""
    upstream_path: str = ""
    redis_url: str = "redis://localhost:6379/0"
    stream_requests: str = "cmux:requests"
    stream_responses: str = "cmux:responses"
    stream_maxlen: int = 10000
    batch_size: int = 50
    flush_interval: float = 0.1
    buffer_size: int = 65536
    connect_timeout: float = 5.0
    idle_timeout: float = 300.0
    log_level: str = "INFO"
    log_file: str | None = None

    def __post_init__(self):
        if not self.listen_path:
            self.listen_path = detect_socket_path()
        if not self.upstream_path:
            sock_dir = os.path.dirname(self.listen_path)
            self.upstream_path = os.path.join(sock_dir, "cmux-real.sock")

    @classmethod
    def from_env_and_args(cls, args: argparse.Namespace) -> "ProxyConfig":
        config = cls()
        # 환경변수 오버라이드
        env_map = {
            "CMUX_PROXY_LISTEN": "listen_path",
            "CMUX_PROXY_UPSTREAM": "upstream_path",
            "CMUX_PROXY_REDIS_URL": "redis_url",
            "CMUX_PROXY_STREAM_REQ": "stream_requests",
            "CMUX_PROXY_STREAM_RES": "stream_responses",
            "CMUX_PROXY_MAXLEN": "stream_maxlen",
            "CMUX_PROXY_LOG_LEVEL": "log_level",
        }
        for env_key, attr in env_map.items():
            val = os.environ.get(env_key)
            if val is not None:
                if attr == "stream_maxlen":
                    setattr(config, attr, int(val))
                else:
                    setattr(config, attr, val)
        # CLI 인자 오버라이드 (최우선)
        if args.listen:
            config.listen_path = args.listen
        if args.upstream:
            config.upstream_path = args.upstream
        if args.redis_url:
            config.redis_url = args.redis_url
        if args.log_level:
            config.log_level = args.log_level
        if args.log_file:
            config.log_file = args.log_file
        return config


class RedisStreamWriter:
    """비동기 배치 Redis Stream 적재기."""

    def __init__(self, config: ProxyConfig):
        self._config = config
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=10000)
        self._redis: aioredis.Redis | None = None
        self._running = False
        self._flush_task: asyncio.Task | None = None

    async def start(self):
        self._running = True
        await self._ensure_connection()
        self._flush_task = asyncio.create_task(self._flush_loop())
        logger.info("RedisStreamWriter 시작")

    async def stop(self):
        self._running = False
        if self._flush_task:
            self._flush_task.cancel()
            try:
                await self._flush_task
            except asyncio.CancelledError:
                pass
        # 잔여 큐 플러시
        await self._flush_batch()
        if self._redis:
            await self._redis.aclose()
            self._redis = None
        logger.info("RedisStreamWriter 종료")

    async def enqueue(self, stream_key: str, entry: dict[str, str]):
        try:
            self._queue.put_nowait((stream_key, entry))
        except asyncio.QueueFull:
            logger.warning("큐 오버플로우, 엔트리 드롭: %s", entry.get("method", "?"))

    async def _flush_loop(self):
        while self._running:
            await asyncio.sleep(self._config.flush_interval)
            if not self._queue.empty():
                await self._flush_batch()

    async def _flush_batch(self):
        if self._queue.empty():
            return
        if not await self._ensure_connection():
            return

        batch: list[tuple[str, dict]] = []
        for _ in range(min(self._config.batch_size, self._queue.qsize())):
            try:
                batch.append(self._queue.get_nowait())
            except asyncio.QueueEmpty:
                break

        if not batch:
            return

        try:
            async with self._redis.pipeline(transaction=False) as pipe:
                for stream_key, entry in batch:
                    pipe.xadd(
                        stream_key, entry,
                        maxlen=self._config.stream_maxlen,
                        approximate=True,
                    )
                await pipe.execute()
        except Exception as e:
            logger.warning("Redis XADD 실패, 재큐잉: %s", e)
            for item in batch:
                try:
                    self._queue.put_nowait(item)
                except asyncio.QueueFull:
                    break
            self._redis = None

    async def _ensure_connection(self) -> bool:
        if self._redis is not None:
            try:
                await self._redis.ping()
                return True
            except Exception:
                self._redis = None

        try:
            self._redis = aioredis.from_url(
                self._config.redis_url,
                decode_responses=True,
            )
            await self._redis.ping()
            logger.info("Redis 연결 성공")
            return True
        except Exception as e:
            logger.warning("Redis 연결 실패: %s", e)
            self._redis = None
            return False


class ConnectionHandler:
    """개별 클라이언트 연결 처리."""

    def __init__(
        self,
        conn_id: str,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
        config: ProxyConfig,
        stream_writer: RedisStreamWriter,
    ):
        self.conn_id = conn_id
        self._client_reader = client_reader
        self._client_writer = client_writer
        self._config = config
        self._stream_writer = stream_writer

    async def run(self):
        upstream_reader = None
        upstream_writer = None
        try:
            upstream_reader, upstream_writer = await self._connect_upstream()
            if upstream_reader is None:
                return

            req_task = asyncio.create_task(
                self._relay_request(self._client_reader, upstream_writer)
            )
            res_task = asyncio.create_task(
                self._relay_response(upstream_reader, self._client_writer)
            )

            done, pending = await asyncio.wait(
                [req_task, res_task],
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            for task in done:
                if task.exception():
                    logger.debug("연결 %s 태스크 예외: %s", self.conn_id, task.exception())

        except Exception as e:
            logger.error("연결 %s 처리 오류: %s", self.conn_id, e)
        finally:
            self._client_writer.close()
            try:
                await self._client_writer.wait_closed()
            except Exception:
                pass
            if upstream_writer:
                upstream_writer.close()
                try:
                    await upstream_writer.wait_closed()
                except Exception:
                    pass
            logger.debug("연결 %s 종료", self.conn_id)

    async def _connect_upstream(self):
        """upstream 소켓에 연결. 재시도 로직 포함 (restart-app 모드 대응)."""
        deadline = time.monotonic() + self._config.connect_timeout
        delay = 0.1
        while True:
            try:
                reader, writer = await asyncio.open_unix_connection(
                    self._config.upstream_path,
                    limit=1024 * 1024,
                )
                return reader, writer
            except (ConnectionRefusedError, FileNotFoundError, OSError) as e:
                if time.monotonic() >= deadline:
                    logger.error("연결 %s: upstream 연결 실패 (타임아웃): %s", self.conn_id, e)
                    return None, None
                logger.debug("연결 %s: upstream 연결 재시도 (%.1fs 후)", self.conn_id, delay)
                await asyncio.sleep(delay)
                delay = min(delay * 2, 1.0)

    async def _relay_request(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        while True:
            line = await reader.readline()
            if not line:
                break
            writer.write(line)
            await writer.drain()

            entry = self._parse_message(line, "request")
            await self._stream_writer.enqueue(self._config.stream_requests, entry)

    async def _relay_response(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        while True:
            line = await reader.readline()
            if not line:
                break
            writer.write(line)
            await writer.drain()

            entry = self._parse_message(line, "response")
            await self._stream_writer.enqueue(self._config.stream_responses, entry)

    def _parse_message(self, raw: bytes, direction: str) -> dict[str, str]:
        ts_ms = str(int(time.time() * 1000))
        data_str = raw.decode("utf-8", errors="replace").rstrip("\n")
        entry: dict[str, str] = {
            "conn_id": self.conn_id,
            "ts": ts_ms,
            "direction": direction,
            "data": data_str,
            "size": str(len(raw)),
        }

        try:
            parsed = json.loads(data_str)
            if direction == "request":
                entry["method"] = parsed.get("method", "")
                entry["req_id"] = str(parsed.get("id", ""))
            else:
                entry["req_id"] = str(parsed.get("id", ""))
                entry["ok"] = str(parsed.get("ok", "")).lower()
                entry["method"] = parsed.get("method", "")
                result = parsed.get("result")
                if isinstance(result, dict):
                    keys = ",".join(list(result.keys())[:20])
                    entry["result_keys"] = keys[:200]
        except (json.JSONDecodeError, TypeError):
            # v1 레거시 텍스트 프로토콜
            tokens = data_str.split()
            if tokens:
                entry["method"] = tokens[0]

        return entry


class CmuxSocketProxy:
    """메인 프록시 서버."""

    def __init__(self, config: ProxyConfig):
        self._config = config
        self._stream_writer = RedisStreamWriter(config)
        self._server: asyncio.Server | None = None
        self._connections: dict[str, asyncio.Task] = {}
        self._shutdown_event = asyncio.Event()

    async def start(self):
        # 스태일 소켓 정리
        await self._cleanup_stale_socket()

        await self._stream_writer.start()

        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=self._config.listen_path,
            limit=1024 * 1024,
        )
        os.chmod(self._config.listen_path, 0o600)

        logger.info("프록시 시작: %s → %s", self._config.listen_path, self._config.upstream_path)

        self._setup_signals()
        await self._shutdown_event.wait()

    async def stop(self):
        logger.info("프록시 종료 시작...")
        if self._server:
            self._server.close()
            await self._server.wait_closed()

        for conn_id, task in self._connections.items():
            task.cancel()
        for task in self._connections.values():
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._connections.clear()

        await self._stream_writer.stop()

        # 소켓 파일 삭제
        try:
            os.unlink(self._config.listen_path)
        except FileNotFoundError:
            pass

        logger.info("프록시 종료 완료")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        conn_id = f"{int(time.time() * 1000)}-{uuid.uuid4().hex[:12]}"
        handler = ConnectionHandler(conn_id, reader, writer, self._config, self._stream_writer)
        task = asyncio.create_task(handler.run())
        self._connections[conn_id] = task

        def on_done(t):
            self._connections.pop(conn_id, None)

        task.add_done_callback(on_done)
        logger.debug("새 연결: %s", conn_id)

    async def _cleanup_stale_socket(self):
        if not os.path.exists(self._config.listen_path):
            return
        logger.info("기존 소켓 파일 제거: %s", self._config.listen_path)
        try:
            os.unlink(self._config.listen_path)
        except FileNotFoundError:
            pass

    def _setup_signals(self):
        loop = asyncio.get_running_loop()

        async def shutdown_handler():
            await self.stop()
            self._shutdown_event.set()

        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, lambda: asyncio.create_task(shutdown_handler()))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="cmux Socket Proxy")
    parser.add_argument("--listen", help="프록시 리스닝 소켓 경로")
    parser.add_argument("--upstream", help="cmux 앱 실제 소켓 경로")
    parser.add_argument("--redis-url", help="Redis 연결 URL")
    parser.add_argument("--log-level", help="로그 레벨 (DEBUG, INFO, WARNING, ERROR)")
    parser.add_argument("--log-file", help="로그 파일 경로")
    return parser.parse_args()


def setup_logging(config: ProxyConfig):
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    if config.log_file:
        handlers.append(logging.FileHandler(config.log_file))
    logging.basicConfig(
        level=getattr(logging, config.log_level.upper(), logging.INFO),
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
        handlers=handlers,
    )


async def main():
    args = parse_args()
    config = ProxyConfig.from_env_and_args(args)
    setup_logging(config)

    logger.info("설정: listen=%s upstream=%s redis=%s",
                config.listen_path, config.upstream_path, config.redis_url)

    proxy = CmuxSocketProxy(config)
    await proxy.start()


if __name__ == "__main__":
    asyncio.run(main())
