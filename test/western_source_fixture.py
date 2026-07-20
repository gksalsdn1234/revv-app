import hashlib
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import TracebackType


class FixtureHttpServer(ThreadingHTTPServer):
    server_port: int


class FixtureHandler(BaseHTTPRequestHandler):
    payload: bytes = b"fixture-pbf"
    request_count: int = 0
    mode: str = "ok"
    server_port: int = 0
    path_counts: dict[str, int] = {}

    def do_GET(self) -> None:
        type(self).request_count += 1
        type(self).path_counts[self.path] = type(self).path_counts.get(self.path, 0) + 1
        filename = self.path.rsplit("/", 1)[-1]
        if type(self).mode == "retry_once" and type(self).path_counts[self.path] == 1:
            self.send_response(500)
            self.end_headers()
            return
        if type(self).mode == "redirect" and filename.endswith(".pbf"):
            self.send_response(302)
            self.send_header(
                "Location", f"http://localhost:{type(self).server_port}/elsewhere"
            )
            self.end_headers()
            return
        if filename.endswith(".md5"):
            province_file = filename.removesuffix(".md5")
            payload = type(self).payload_for(province_file)
            body = f"{hashlib.md5(payload).hexdigest()}  {province_file}\n".encode()
        elif type(self).mode == "oversize":
            body = type(self).payload_for(filename) * 100
        else:
            body = type(self).payload_for(filename)
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if type(self).mode == "slow" and filename.endswith(".md5"):
            time.sleep(0.2)
        interrupted = type(self).mode == "interrupt" and filename.endswith(".pbf")
        interrupted = interrupted or (
            type(self).mode == "interrupt-after-ab"
            and filename.startswith("british-columbia-")
            and filename.endswith(".pbf")
        )
        if interrupted:
            self.wfile.write(body[: max(1, len(body) // 2)])
            self.wfile.flush()
            self.close_connection = True
            return
        self.wfile.write(body)

    @classmethod
    def payload_for(cls, filename: str) -> bytes:
        return cls.payload + b":" + filename.encode("ascii")

    def log_message(self, format: str, *args: str | int | float) -> None:
        return


class FixtureServer:
    def __init__(self) -> None:
        FixtureHandler.request_count = 0
        FixtureHandler.mode = "ok"
        FixtureHandler.path_counts = {}
        self.server = FixtureHttpServer(("127.0.0.1", 0), FixtureHandler)
        FixtureHandler.server_port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self) -> "FixtureServer":
        self.thread.start()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()

    @property
    def origin(self) -> str:
        return f"http://127.0.0.1:{self.server.server_port}"


def write_fixture_manifest(
    path: Path,
    origin: str,
    *,
    checksum: str | None = None,
    size: int | None = None,
) -> None:
    sources = []
    hubs = []
    provinces = (
        ("AB", "alberta"),
        ("BC", "british-columbia"),
        ("MB", "manitoba"),
        ("SK", "saskatchewan"),
    )
    for code, slug in provinces:
        filename = f"{slug}-260715.osm.pbf"
        payload = FixtureHandler.payload_for(filename)
        sources.append(
            {
                "province_code": code,
                "snapshot": "2026-07-15",
                "url": f"{origin}/{filename}",
                "checksum_url": f"{origin}/{filename}.md5",
                "checksum": checksum or hashlib.md5(payload).hexdigest(),
                "size_bytes": size or len(payload),
            }
        )
        hubs.append(
            {
                "hub_id": f"{code.lower()}-fixture",
                "province_code": code,
                "bounds": {
                    "min_lat": 49.0,
                    "min_lng": -120.0,
                    "max_lat": 50.0,
                    "max_lng": -119.0,
                },
            }
        )
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "generator_version": "western-source-v1",
                "snapshot": "2026-07-15",
                "sources": sources,
                "hubs": hubs,
            }
        ),
        encoding="utf-8",
    )


def write_fake_osmium(
    path: Path, *, create_output: bool = True, sleep_seconds: float = 0.0
) -> None:
    output_action = (
        "Path(args[args.index('-o') + 1]).write_bytes("
        "Path(args[-1]).read_bytes() + b':' + args[args.index('-b') + 1].encode())"
        if create_output
        else "pass"
    )
    sleep_action = f"time.sleep({sleep_seconds})" if sleep_seconds > 0 else "pass"
    path.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\nimport time\nfrom pathlib import Path\nargs=sys.argv[1:]\n"
        "if args[0] == 'extract':\n    "
        + sleep_action
        + "\n    "
        + output_action
        + "\n"
        "elif args[0] == 'fileinfo':\n    sys.exit(0)\n"
        "elif args[0] == '--version':\n    print('osmium version 1.19.0')\n",
        encoding="utf-8",
    )
    path.chmod(0o755)
