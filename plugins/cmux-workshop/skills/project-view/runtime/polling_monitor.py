#!/usr/bin/env python3
"""cmux 터미널 화면 폴링 모니터 — read-screen 기반 화면 변화 감지 및 Redis Stream 적재."""

import argparse
import asyncio
import hashlib
import json
import logging
import os
import signal
import subprocess
import time

import redis.asyncio as aioredis

logger = logging.getLogger("polling-monitor")

STREAM_TERMINAL = "cmux:terminal_output"
MAXLEN = 50000


def detect_socket_path() -> str:
    try:
        result = subprocess.run(
            ["cmux", "identify", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        return json.loads(result.stdout)["socket_path"]
    except Exception as e:
        logger.warning("cmux identify 실패: %s", e)
        return "/tmp/cmux.sock"


async def cmux_rpc(sock_path: str, method: str, params: dict | None = None) -> dict:
    """cmux 소켓에 JSON-RPC 호출."""
    request = json.dumps({
        "id": f"poll-{int(time.time() * 1000)}",
        "method": method,
        "params": params or {},
    })
    reader, writer = await asyncio.open_unix_connection(sock_path)
    try:
        writer.write(request.encode() + b"\n")
        await writer.drain()
        line = await asyncio.wait_for(reader.readline(), timeout=5.0)
        return json.loads(line.decode())
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


class ScreenPoller:
    """단일 surface의 화면을 폴링하여 변경 감지."""

    def __init__(self, surface_id: str, workspace_id: str, sock_path: str):
        self.surface_id = surface_id
        self.workspace_id = workspace_id
        self.sock_path = sock_path
        self.prev_lines: list[str] = []
        self.prev_hash: str = ""

    async def poll_once(self) -> dict | None:
        """한 번 폴링. 변경 시 diff 엔트리 반환, 변경 없으면 None."""
        text = await self._read_screen()
        if text is None:
            return None

        current_hash = hashlib.md5(text.encode()).hexdigest()
        if current_hash == self.prev_hash:
            return None

        current_lines = text.split("\n")
        changed = {}
        max_len = max(len(current_lines), len(self.prev_lines))
        for i in range(max_len):
            curr = current_lines[i] if i < len(current_lines) else ""
            prev = self.prev_lines[i] if i < len(self.prev_lines) else ""
            if curr != prev:
                changed[str(i)] = curr

        self.prev_lines = current_lines
        self.prev_hash = current_hash

        return {
            "surface_id": self.surface_id,
            "workspace_id": self.workspace_id,
            "ts": str(int(time.time() * 1000)),
            "event": "screen_changed",
            "changed_lines": json.dumps(list(changed.keys())),
            "diff": json.dumps(changed, ensure_ascii=False),
            "line_count": str(len(current_lines)),
        }

    async def snapshot(self) -> dict | None:
        """전체 스냅샷 엔트리 반환."""
        text = await self._read_screen()
        if text is None:
            return None

        self.prev_lines = text.split("\n")
        self.prev_hash = hashlib.md5(text.encode()).hexdigest()

        return {
            "surface_id": self.surface_id,
            "workspace_id": self.workspace_id,
            "ts": str(int(time.time() * 1000)),
            "event": "screen_snapshot",
            "full_text": text,
            "line_count": str(len(self.prev_lines)),
        }

    async def _read_screen(self) -> str | None:
        try:
            resp = await cmux_rpc(self.sock_path, "surface.read_text", {
                "surface_id": self.surface_id,
                "scrollback": False,
            })
            if resp.get("ok") and resp.get("result"):
                return resp["result"].get("text", "")
            return None
        except Exception as e:
            logger.debug("read_screen 실패 (%s): %s", self.surface_id, e)
            return None


class PollingMonitor:
    """전체 surface를 관리하며 폴링 루프 실행."""

    def __init__(
        self,
        sock_path: str,
        redis_url: str,
        interval: float = 1.0,
        snapshot_interval: float = 30.0,
        target_surface: str | None = None,
        target_workspace: str | None = None,
    ):
        self.sock_path = sock_path
        self.redis_url = redis_url
        self.interval = interval
        self.snapshot_interval = snapshot_interval
        self.target_surface = target_surface
        self.target_workspace = target_workspace
        self._pollers: dict[str, ScreenPoller] = {}
        self._redis: aioredis.Redis | None = None
        self._running = False

    async def start(self):
        self._running = True
        self._redis = aioredis.from_url(self.redis_url, decode_responses=True)

        try:
            await self._redis.ping()
            logger.info("Redis 연결 성공")
        except Exception as e:
            logger.warning("Redis 연결 실패 (계속 시도): %s", e)

        # 시그널 핸들러
        loop = asyncio.get_running_loop()
        stop_event = asyncio.Event()

        def on_signal():
            self._running = False
            stop_event.set()

        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, on_signal)

        # 초기 surface 목록
        await self._refresh_surfaces()

        if not self._pollers:
            logger.warning("모니터링할 surface가 없습니다")

        # 태스크 시작
        poll_task = asyncio.create_task(self._poll_loop())
        refresh_task = asyncio.create_task(self._refresh_loop())
        snapshot_task = asyncio.create_task(self._snapshot_loop())

        logger.info(
            "폴링 모니터 시작: %d surfaces, interval=%.1fs, snapshot=%.0fs",
            len(self._pollers), self.interval, self.snapshot_interval,
        )

        await stop_event.wait()

        for task in (poll_task, refresh_task, snapshot_task):
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        if self._redis:
            await self._redis.aclose()
        logger.info("폴링 모니터 종료")

    async def _poll_loop(self):
        while self._running:
            for poller in list(self._pollers.values()):
                entry = await poller.poll_once()
                if entry:
                    await self._write_entry(entry)
            await asyncio.sleep(self.interval)

    async def _snapshot_loop(self):
        while self._running:
            await asyncio.sleep(self.snapshot_interval)
            for poller in list(self._pollers.values()):
                entry = await poller.snapshot()
                if entry:
                    await self._write_entry(entry)
            logger.debug("스냅샷 완료: %d surfaces", len(self._pollers))

    async def _refresh_loop(self):
        while self._running:
            await asyncio.sleep(30.0)
            await self._refresh_surfaces()

    async def _refresh_surfaces(self):
        if self.target_surface:
            if self.target_surface not in self._pollers:
                self._pollers[self.target_surface] = ScreenPoller(
                    self.target_surface, "", self.sock_path,
                )
            return

        try:
            resp = await cmux_rpc(self.sock_path, "surface.list", {})
            if not resp.get("ok"):
                return

            surfaces = resp.get("result", {}).get("surfaces", [])
            ws_ref = resp.get("result", {}).get("workspace_ref", "")

            if self.target_workspace and ws_ref != self.target_workspace:
                # 타겟 워크스페이스 지정 시 해당 워크스페이스의 surface.list 호출
                for ws_resp in await self._list_all_workspaces():
                    if ws_resp.get("workspace_ref") == self.target_workspace:
                        surfaces = ws_resp.get("surfaces", [])
                        ws_ref = self.target_workspace
                        break

            current_ids = set()
            for s in surfaces:
                sid = s.get("ref", "")
                if not sid:
                    continue
                current_ids.add(sid)
                if sid not in self._pollers:
                    self._pollers[sid] = ScreenPoller(sid, ws_ref, self.sock_path)
                    logger.info("Surface 추가: %s (%s)", sid, s.get("title", ""))

            # 닫힌 surface 제거
            for sid in list(self._pollers.keys()):
                if sid not in current_ids and not self.target_surface:
                    del self._pollers[sid]
                    logger.info("Surface 제거: %s", sid)

        except Exception as e:
            logger.warning("surface 목록 갱신 실패: %s", e)

    async def _list_all_workspaces(self) -> list[dict]:
        """모든 워크스페이스의 surface 목록."""
        results = []
        try:
            ws_resp = await cmux_rpc(self.sock_path, "workspace.list", {})
            if not ws_resp.get("ok"):
                return results
            for ws in ws_resp.get("result", {}).get("workspaces", []):
                ws_ref = ws.get("ref", "")
                surf_resp = await cmux_rpc(
                    self.sock_path, "surface.list",
                    {"workspace_ref": ws_ref},
                )
                if surf_resp.get("ok"):
                    result = surf_resp.get("result", {})
                    result["workspace_ref"] = ws_ref
                    results.append(result)
        except Exception as e:
            logger.warning("워크스페이스 조회 실패: %s", e)
        return results

    async def _write_entry(self, entry: dict):
        if not self._redis:
            return
        try:
            await self._redis.xadd(
                STREAM_TERMINAL, entry,
                maxlen=MAXLEN, approximate=True,
            )
        except Exception as e:
            logger.warning("Redis XADD 실패: %s", e)
            try:
                self._redis = aioredis.from_url(self.redis_url, decode_responses=True)
            except Exception:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="cmux 터미널 화면 폴링 모니터")
    parser.add_argument("--surface", help="모니터링할 surface ID (예: surface:1)")
    parser.add_argument("--workspace", help="특정 워크스페이스만 (예: workspace:2)")
    parser.add_argument("--all", action="store_true", help="모든 surface 자동 감지 (기본)")
    parser.add_argument("--interval", type=float, default=1.0, help="폴링 간격 초 (기본: 1.0)")
    parser.add_argument("--snapshot-interval", type=float, default=30.0, help="전체 스냅샷 간격 (기본: 30)")
    parser.add_argument("--redis-url", default="redis://localhost:6379/0")
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


async def main():
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
    )

    sock_path = detect_socket_path()
    logger.info("소켓 경로: %s", sock_path)

    monitor = PollingMonitor(
        sock_path=sock_path,
        redis_url=args.redis_url,
        interval=args.interval,
        snapshot_interval=args.snapshot_interval,
        target_surface=args.surface,
        target_workspace=args.workspace,
    )
    await monitor.start()


if __name__ == "__main__":
    asyncio.run(main())
