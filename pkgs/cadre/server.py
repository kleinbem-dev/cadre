#!/usr/bin/env python3
"""Lightweight static SPA + local-inference telemetry server for Cadre Web."""

import argparse
from http import HTTPStatus
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
import signal
import socket
import sys
import threading
import time
import urllib.parse

MAX_CHAT_BODY_BYTES = 262_144
STATUS_CACHE_TTL_SEC = 2.0
LOOPBACK_HOSTS = {"127.0.0.1", "::1", "localhost"}

CSP_POLICY = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data:; "
    "font-src 'self' data:; "
    "connect-src 'self'; "
    "object-src 'none'; "
    "base-uri 'self'; "
    "frame-ancestors 'none'"
)


def parse_loopback_endpoint(raw: str, flag: str) -> tuple[str, int]:
    parsed = urllib.parse.urlparse(raw)
    host = parsed.hostname or ""
    port = parsed.port or 0
    if parsed.scheme != "http" or host not in LOOPBACK_HOSTS or not (1 <= port <= 65535):
        raise ValueError(f"{flag} must be an http:// loopback URL with an explicit port, got: {raw!r}")
    return host, port


def http_get_json(endpoint: tuple[str, int], path: str, timeout: float = 1.5) -> tuple[dict | None, int]:
    start = time.monotonic()
    conn = http.client.HTTPConnection(endpoint[0], endpoint[1], timeout=timeout)
    try:
        conn.request("GET", path, headers={"Accept": "application/json"})
        resp = conn.getresponse()
        raw = resp.read(1_048_576)
        if resp.status != 200:
            return None, 0
        data = json.loads(raw.decode("utf-8"))
        latency_ms = max(1, round((time.monotonic() - start) * 1000))
        return (data if isinstance(data, dict) else None), latency_ms
    except (OSError, ValueError, http.client.HTTPException):
        return None, 0
    finally:
        conn.close()


def http_post_json(endpoint: tuple[str, int], path: str, body: dict, timeout: float = 120.0) -> tuple[int, dict | str]:
    encoded = json.dumps(body).encode("utf-8")
    conn = http.client.HTTPConnection(endpoint[0], endpoint[1], timeout=timeout)
    try:
        conn.request(
            "POST",
            path,
            body=encoded,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        resp = conn.getresponse()
        raw = resp.read(2_097_152)
        if resp.status != 200:
            return resp.status, raw[:4096].decode("utf-8", errors="replace")
        parsed = json.loads(raw.decode("utf-8"))
        return 200, (parsed if isinstance(parsed, dict) else {})
    finally:
        conn.close()


class StatusCache:
    def __init__(
        self,
        configured_backend: str,
        default_model: str,
        mesh_ep: tuple[str, int],
        ollama_ep: tuple[str, int],
        chat_enabled: bool,
    ):
        self.configured_backend = configured_backend
        self.default_model = default_model
        self.mesh_ep = mesh_ep
        self.ollama_ep = ollama_ep
        self.chat_enabled = chat_enabled
        self.hostname = socket.gethostname() or "localhost"
        self._lock = threading.Lock()
        self._cached_at = 0.0
        self._payload: dict | None = None

    def get(self, force: bool = False) -> dict:
        now = time.monotonic()
        with self._lock:
            if not force and self._payload is not None and (now - self._cached_at) < STATUS_CACHE_TTL_SEC:
                return self._payload
        payload = self._probe()
        with self._lock:
            self._payload = payload
            self._cached_at = time.monotonic()
        return payload

    def _probe(self) -> dict:
        nodes: list[dict] = []
        mesh_models: list[str] = []
        ollama_models: list[str] = []

        if self.configured_backend in ("auto", "mesh"):
            inv, latency_ms = http_get_json(self.mesh_ep, "/v1/models")
            if inv is not None:
                raw_models = inv.get("data")
                if isinstance(raw_models, list):
                    mesh_models = [str(m["id"]) for m in raw_models if isinstance(m, dict) and m.get("id")]
                nodes.append({
                    "id": "local-mesh",
                    "host": self.hostname,
                    "nodeType": "gpu-box",
                    "backend": "mesh",
                    "activeModel": mesh_models[0] if mesh_models else (self.default_model or "idle"),
                    "models": mesh_models,
                    "vramUsedGb": 0.0,
                    "vramTotalGb": 0.0,
                    "tokensPerSec": 0.0,
                    "latencyMs": latency_ms,
                    "status": "healthy" if mesh_models else "degraded",
                })

        if self.configured_backend in ("auto", "ollama"):
            tags, latency_ms = http_get_json(self.ollama_ep, "/api/tags")
            if tags is not None:
                raw_tags = tags.get("models")
                if isinstance(raw_tags, list):
                    ollama_models = [str(m["name"]) for m in raw_tags if isinstance(m, dict) and m.get("name")]
                vram_used_gb = 0.0
                active_ollama = ollama_models[0] if ollama_models else (self.default_model or "idle")
                ps_data, _ = http_get_json(self.ollama_ep, "/api/ps", timeout=1.0)
                if ps_data and isinstance(ps_data.get("models"), list) and ps_data["models"]:
                    first_loaded = ps_data["models"][0]
                    if isinstance(first_loaded, dict):
                        active_ollama = str(first_loaded.get("name") or active_ollama)
                        vram_bytes = sum(
                            int(m.get("size_vram") or m.get("size") or 0)
                            for m in ps_data["models"]
                            if isinstance(m, dict)
                        )
                        vram_used_gb = round(vram_bytes / (1024**3), 1)
                nodes.append({
                    "id": "local-ollama",
                    "host": self.hostname,
                    "nodeType": "laptop",
                    "backend": "ollama",
                    "activeModel": active_ollama,
                    "models": ollama_models,
                    "vramUsedGb": vram_used_gb,
                    "vramTotalGb": 0.0,
                    "tokensPerSec": 0.0,
                    "latencyMs": latency_ms,
                    "status": "healthy",
                })

        if mesh_models or any(n["backend"] == "mesh" for n in nodes):
            active_backend = "mesh"
            resolved_model = mesh_models[0] if mesh_models else (self.default_model or "Qwen3-8B-Q4_K_M")
        elif any(n["backend"] == "ollama" for n in nodes):
            active_backend = "ollama"
            resolved_model = ollama_models[0] if ollama_models else (self.default_model or "qwen2.5-coder")
        else:
            active_backend = "standby"
            resolved_model = self.default_model or (
                "qwen2.5-coder" if self.configured_backend == "ollama" else "Qwen3-8B-Q4_K_M"
            )

        return {
            "activeBackend": active_backend,
            "configuredBackend": self.configured_backend,
            "defaultModel": resolved_model,
            "chatEnabled": self.chat_enabled,
            "host": self.hostname,
            "nodes": nodes,
        }


def make_handler(
    static_root: str,
    status_cache: StatusCache,
    mesh_ep: tuple[str, int],
    ollama_ep: tuple[str, int],
):
    real_root = os.path.realpath(static_root)

    class CadreHandler(BaseHTTPRequestHandler):
        server_version = "cadre-web/0.1"

        def log_message(self, fmt: str, *args) -> None:
            return

        def _send_security_headers(self, cache_control: str = "no-cache") -> None:
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", CSP_POLICY)
            self.send_header("Cache-Control", cache_control)

        def _send_json(self, status: int, obj: dict, head_only: bool = False) -> None:
            raw = json.dumps(obj).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self._send_security_headers("no-store")
            self.end_headers()
            if not head_only:
                self.wfile.write(raw)

        def do_HEAD(self) -> None:
            self._handle_get(head_only=True)

        def do_GET(self) -> None:
            self._handle_get(head_only=False)

        def _handle_get(self, head_only: bool) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path == "/health":
                self._send_json(HTTPStatus.OK, {"status": "ok"}, head_only=head_only)
                return

            if path == "/api/status":
                refresh = urllib.parse.parse_qs(parsed.query).get("refresh") == ["1"]
                self._send_json(HTTPStatus.OK, status_cache.get(force=refresh), head_only=head_only)
                return

            rel = urllib.parse.unquote(path).lstrip("/")
            candidate = os.path.realpath(os.path.join(real_root, rel or "index.html"))
            if candidate != real_root and not candidate.startswith(real_root + os.sep):
                self._send_json(HTTPStatus.FORBIDDEN, {"error": "forbidden"}, head_only=head_only)
                return

            if os.path.isdir(candidate):
                candidate = os.path.join(candidate, "index.html")

            if not os.path.isfile(candidate):
                # SPA fallback applies only to extensionless client routes, never missing static assets.
                last_seg = path.rsplit("/", 1)[-1]
                if "." not in last_seg and not path.startswith("/api/"):
                    for fallback_name in ("200.html", "index.html"):
                        fb = os.path.realpath(os.path.join(real_root, fallback_name))
                        if fb.startswith(real_root + os.sep) and os.path.isfile(fb):
                            candidate = fb
                            break
                if not os.path.isfile(candidate):
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"}, head_only=head_only)
                    return

            ctype, _ = mimetypes.guess_type(candidate)
            ctype = ctype or "application/octet-stream"
            if ctype.startswith(("text/", "application/javascript", "application/json", "image/svg+xml")):
                ctype = f"{ctype}; charset=utf-8"

            cache_ctl = (
                "public, max-age=31536000, immutable"
                if "/_app/immutable/" in path
                else "no-cache"
            )
            try:
                with open(candidate, "rb") as f:
                    body = f.read()
            except OSError:
                self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "read error"}, head_only=head_only)
                return

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self._send_security_headers(cache_ctl)
            self.end_headers()
            if not head_only:
                self.wfile.write(body)

        def do_POST(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path != "/api/chat":
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return

            if not status_cache.chat_enabled:
                self._send_json(
                    HTTPStatus.FORBIDDEN,
                    {
                        "error": (
                            "Chat proxy is disabled on non-loopback listeners. "
                            "Run 'cadre web' locally or enable services.cadre.web.enableChatProxy."
                        )
                    },
                )
                return

            try:
                length = int(self.headers.get("Content-Length") or "0")
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid Content-Length"})
                return

            if length <= 0 or length > MAX_CHAT_BODY_BYTES:
                self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "request body out of bounds"})
                return

            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid JSON body"})
                return

            if not isinstance(payload, dict):
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "JSON object required"})
                return

            raw_msgs = payload.get("messages")
            if not isinstance(raw_msgs, list) or not raw_msgs:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "non-empty messages list required"})
                return

            clean_msgs = []
            for m in raw_msgs[-32:]:
                if not isinstance(m, dict):
                    continue
                role = m.get("role")
                content = m.get("content")
                if role in ("system", "user", "assistant") and isinstance(content, str) and content.strip():
                    clean_msgs.append({"role": role, "content": content[:32_768]})

            if not clean_msgs:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "no valid chat messages"})
                return

            status = status_cache.get()
            req_backend = payload.get("backend")
            if req_backend not in ("mesh", "ollama"):
                req_backend = (
                    status["activeBackend"]
                    if status["activeBackend"] in ("mesh", "ollama")
                    else ("ollama" if status["configuredBackend"] == "ollama" else "mesh")
                )

            model = payload.get("model")
            if not isinstance(model, str) or not model.strip():
                model = status["defaultModel"]

            upstream_ep = ollama_ep if req_backend == "ollama" else mesh_ep
            started = time.monotonic()
            try:
                code, resp_payload = http_post_json(
                    upstream_ep,
                    "/v1/chat/completions",
                    {"model": model, "messages": clean_msgs, "stream": False},
                )
            except (OSError, ValueError, http.client.HTTPException) as exc:
                self._send_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {"error": f"Local {req_backend} backend is unreachable ({exc}). Start it with 'cadre serve'."},
                )
                return

            if code != 200 or not isinstance(resp_payload, dict):
                self._send_json(
                    HTTPStatus.BAD_GATEWAY,
                    {"error": f"Upstream {req_backend} HTTP {code}: {resp_payload}"},
                )
                return

            choices = resp_payload.get("choices")
            first_msg = choices[0].get("message", {}) if isinstance(choices, list) and choices else {}
            reply = str(first_msg.get("content") or "").strip()
            used_model = str(resp_payload.get("model") or model)
            latency_ms = max(1, round((time.monotonic() - started) * 1000))
            self._send_json(
                HTTPStatus.OK,
                {
                    "reply": reply,
                    "model": used_model,
                    "backend": req_backend,
                    "latencyMs": latency_ms,
                },
            )

    return CadreHandler


def main() -> int:
    parser = argparse.ArgumentParser(description="Cadre Web static SPA and local telemetry server")
    parser.add_argument("--host", default=os.environ.get("CADRE_WEB_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CADRE_WEB_PORT", "8384")))
    parser.add_argument("--static-dir", required=True)
    parser.add_argument("--backend", choices=("auto", "mesh", "ollama"), default="auto")
    parser.add_argument("--default-model", default="")
    parser.add_argument("--mesh-url", default="http://127.0.0.1:9337")
    parser.add_argument("--ollama-url", default="http://127.0.0.1:11434")
    parser.add_argument("--enable-chat-proxy", action="store_true")
    args = parser.parse_args()

    if not (1 <= args.port <= 65535):
        print(f"Invalid port: {args.port}", file=sys.stderr)
        return 2
    if not os.path.isdir(args.static_dir):
        print(f"Static assets directory not found: {args.static_dir}", file=sys.stderr)
        return 1

    try:
        mesh_ep = parse_loopback_endpoint(args.mesh_url, "--mesh-url")
        ollama_ep = parse_loopback_endpoint(args.ollama_url, "--ollama-url")
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    chat_enabled = args.enable_chat_proxy or (args.host in LOOPBACK_HOSTS)
    status_cache = StatusCache(
        configured_backend=args.backend,
        default_model=args.default_model,
        mesh_ep=mesh_ep,
        ollama_ep=ollama_ep,
        chat_enabled=chat_enabled,
    )
    handler = make_handler(args.static_dir, status_cache, mesh_ep, ollama_ep)

    ThreadingHTTPServer.allow_reuse_address = True
    httpd = ThreadingHTTPServer((args.host, args.port), handler)

    def _stop(_signum: int, _frame) -> None:
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
