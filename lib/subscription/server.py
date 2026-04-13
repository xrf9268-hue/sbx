#!/usr/bin/env python3
"""Minimal adaptive subscription HTTP endpoint for sbx.

The server reads three cached payloads from SBX_SUB_CACHE_DIR and dispatches
them based on the User-Agent of the request:

    clash/meta/stash/mihomo           -> clash.yaml  (text/yaml)
    shadowrocket/quantumult/surge/loon -> uri.txt     (text/plain)
    anything else                      -> base64      (text/plain)

Bind host/port, URL path, and token are taken from state.json via
SBX_SUB_STATE_FILE so that rotating the token or toggling enable flags does
not require any code changes in the HTTP layer.

This script is intentionally dependency-free: only stdlib modules are used.
"""
from __future__ import annotations

import hmac
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

CACHE_DIR = os.environ.get("SBX_SUB_CACHE_DIR", "/var/lib/sbx/subscription")
STATE_FILE = os.environ.get("SBX_SUB_STATE_FILE", "/etc/sing-box/state.json")

FILE_FOR_FORMAT = {
    "clash": ("clash.yaml", "text/yaml; charset=utf-8"),
    "uri": ("uri.txt", "text/plain; charset=utf-8"),
    "base64": ("base64", "text/plain; charset=utf-8"),
}

CLASH_RE = re.compile(r"clash|meta|stash|mihomo", re.IGNORECASE)
URI_RE = re.compile(r"shadowrocket|quantumult|surge|loon", re.IGNORECASE)


def pick_format(user_agent: str) -> str:
    if not user_agent:
        return "base64"
    if CLASH_RE.search(user_agent):
        return "clash"
    if URI_RE.search(user_agent):
        return "uri"
    return "base64"


def load_state() -> dict:
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fp:
            return json.load(fp)
    except (OSError, json.JSONDecodeError):
        return {}


def subscription_config() -> dict:
    state = load_state()
    sub = state.get("subscription") or {}
    return {
        "enabled": bool(sub.get("enabled", False)),
        "bind": sub.get("bind") or "127.0.0.1",
        "port": int(sub.get("port") or 8838),
        "path": sub.get("path") or "/sub",
        "token": sub.get("token") or "",
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "sbx-subscription/1.0"

    # Silence default request logging (systemd journal will capture stderr only).
    def log_message(self, format, *args):  # noqa: A002,N802 - stdlib signature
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _send(self, status: int, body: bytes, content_type: str = "text/plain; charset=utf-8") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _deny(self, status: int, reason: str) -> None:
        self._send(status, (reason + "\n").encode("utf-8"))

    def do_HEAD(self):  # noqa: N802 - stdlib hook
        self.do_GET()

    def do_GET(self):  # noqa: N802 - stdlib hook
        cfg = subscription_config()
        if not cfg["enabled"]:
            self._deny(503, "subscription disabled")
            return

        expected_path = cfg["path"].rstrip("/")
        token = cfg["token"]
        path = self.path.split("?", 1)[0].rstrip("/")

        authorized = False
        if token:
            authorized = hmac.compare_digest(
                path.encode(), f"{expected_path}/{token}".encode()
            )
        else:
            authorized = path == expected_path

        if not authorized:
            self._deny(401, "unauthorized")
            return

        fmt = pick_format(self.headers.get("User-Agent", ""))
        filename, content_type = FILE_FOR_FORMAT[fmt]
        cache_path = os.path.join(CACHE_DIR, filename)

        try:
            with open(cache_path, "rb") as fp:
                body = fp.read()
        except OSError:
            self._deny(503, "subscription cache unavailable")
            return

        self._send(200, body, content_type)


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    cfg = subscription_config()
    if not cfg["enabled"]:
        print("subscription disabled in state.json; exiting", file=sys.stderr)
        return 0

    addr = (cfg["bind"], cfg["port"])
    try:
        server = ThreadingHTTPServer(addr, Handler)
    except OSError as exc:
        print(f"failed to bind {addr}: {exc}", file=sys.stderr)
        return 1

    print(f"sbx-subscription listening on http://{cfg['bind']}:{cfg['port']}{cfg['path']}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
