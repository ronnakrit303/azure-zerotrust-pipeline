"""Minimal HTTP API for DevSecOps pipeline scanning and smoke tests."""

from __future__ import annotations

from datetime import UTC, datetime
import json
import logging
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse
from uuid import uuid4

from zerotrust_demo.config import Settings


CONTROL_EVIDENCE: list[dict[str, str]] = [
    {
        "pillar": "identity",
        "control": "Conditional Access",
        "status": "planned",
        "evidence": "Bicep identity module creates report-only Conditional Access policies.",
    },
    {
        "pillar": "network",
        "control": "Private connectivity",
        "status": "implemented",
        "evidence": "VNet, subnets, and NSG default-deny inbound rules are defined in infra modules.",
    },
    {
        "pillar": "secrets",
        "control": "Secret scanning",
        "status": "implemented",
        "evidence": "Gitleaks and Semgrep secrets rules run before later CI stages.",
    },
    {
        "pillar": "monitoring",
        "control": "Sentinel detections",
        "status": "implemented",
        "evidence": "KQL rules cover lateral movement, privilege escalation, and secrets exfiltration.",
    },
]

ALLOWED_EVENT_TYPES = {
    "auth.failure",
    "auth.success",
    "privilege.change",
    "secret.access",
    "policy.violation",
}
ALLOWED_SEVERITIES = {"Low", "Medium", "High", "Critical"}


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")


def log_access(settings: Settings, request_id: str, method: str, path: str, status_code: int) -> None:
    logging.info(
        json.dumps(
            {
                "timestamp": utc_now(),
                "service": settings.service_name,
                "environment": settings.environment,
                "requestId": request_id,
                "method": method,
                "path": path,
                "statusCode": status_code,
            },
            separators=(",", ":"),
        )
    )


def security_headers(settings: Settings, request_id: str) -> dict[str, str]:
    headers = {
        "Cache-Control": "no-store",
        "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "X-Request-ID": request_id,
    }
    if settings.require_https:
        headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return headers


def normalize_request_id(value: str | None) -> str:
    if not value:
        return str(uuid4())
    cleaned = "".join(character for character in value if character.isalnum() or character in {"-", "_"})
    return cleaned[:64] if cleaned else str(uuid4())


def validate_security_event(payload: dict[str, Any]) -> tuple[dict[str, str], list[str]]:
    errors: list[str] = []
    event_type = str(payload.get("eventType", "")).strip()
    severity = str(payload.get("severity", "")).strip()
    account_name = str(payload.get("accountName", "unknown")).strip() or "unknown"
    ip_address = str(payload.get("ipAddress", "unknown")).strip() or "unknown"

    if event_type not in ALLOWED_EVENT_TYPES:
        errors.append("eventType is not supported")
    if severity not in ALLOWED_SEVERITIES:
        errors.append("severity is not supported")
    if len(account_name) > 256:
        errors.append("accountName is too long")
    if len(ip_address) > 128:
        errors.append("ipAddress is too long")

    return {
        "eventType": event_type,
        "severity": severity,
        "accountName": account_name,
        "ipAddress": ip_address,
    }, errors


def build_handler(settings: Settings) -> type[BaseHTTPRequestHandler]:
    class ZeroTrustRequestHandler(BaseHTTPRequestHandler):
        server_version = "ZeroTrustDemo/1.0"

        def _request_id(self) -> str:
            return normalize_request_id(self.headers.get("X-Request-ID"))

        def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
            request_id = self._request_id()
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status.value)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            for header, value in security_headers(settings, request_id).items():
                self.send_header(header, value)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            log_access(settings, request_id, self.command, urlparse(self.path).path, status.value)

        def _read_json_body(self) -> tuple[dict[str, Any] | None, HTTPStatus | None, str | None]:
            content_type = self.headers.get("Content-Type", "")
            if "application/json" not in content_type.lower():
                return None, HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "Content-Type must be application/json"

            try:
                content_length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return None, HTTPStatus.BAD_REQUEST, "Content-Length must be a valid integer"

            if content_length <= 0:
                return None, HTTPStatus.BAD_REQUEST, "Request body is required"
            if content_length > settings.max_body_bytes:
                return None, HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "Request body is too large"

            raw_body = self.rfile.read(content_length)
            try:
                payload = json.loads(raw_body.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                return None, HTTPStatus.BAD_REQUEST, "Request body must be valid JSON"

            if not isinstance(payload, dict):
                return None, HTTPStatus.BAD_REQUEST, "Request body must be a JSON object"
            return payload, None, None

        def do_HEAD(self) -> None:
            self.do_GET()

        def do_GET(self) -> None:
            path = urlparse(self.path).path
            if settings.require_https and self.headers.get("X-Forwarded-Proto", "http") != "https":
                self._send_json(
                    HTTPStatus.UPGRADE_REQUIRED,
                    {"status": "error", "message": "HTTPS is required"},
                )
                return

            if path == "/healthz":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "timestamp": utc_now(),
                        **settings.public_metadata(),
                    },
                )
                return

            if path == "/readyz":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ready",
                        "checks": [
                            {"name": "configuration", "status": "ok"},
                            {"name": "logging", "status": "ok"},
                            {"name": "securityHeaders", "status": "ok"},
                        ],
                    },
                )
                return

            if path == "/api/v1/posture":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "generatedAt": utc_now(),
                        "controls": CONTROL_EVIDENCE,
                    },
                )
                return

            self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "Route not found"})

        def do_POST(self) -> None:
            path = urlparse(self.path).path
            if settings.require_https and self.headers.get("X-Forwarded-Proto", "http") != "https":
                self._send_json(
                    HTTPStatus.UPGRADE_REQUIRED,
                    {"status": "error", "message": "HTTPS is required"},
                )
                return

            if path != "/api/v1/events/security":
                self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "Route not found"})
                return

            payload, error_status, error_message = self._read_json_body()
            if error_status is not None:
                self._send_json(error_status, {"status": "error", "message": error_message})
                return

            event, errors = validate_security_event(payload or {})
            if errors:
                self._send_json(
                    HTTPStatus.BAD_REQUEST,
                    {"status": "error", "message": "Invalid security event", "errors": errors},
                )
                return

            self._send_json(
                HTTPStatus.ACCEPTED,
                {
                    "status": "accepted",
                    "eventId": str(uuid4()),
                    "receivedAt": utc_now(),
                    "classification": {
                        "eventType": event["eventType"],
                        "severity": event["severity"],
                    },
                    "routing": "sentinel",
                },
            )

        def log_message(self, format: str, *args: Any) -> None:
            return

        def version_string(self) -> str:
            return self.server_version

    return ZeroTrustRequestHandler


def create_server(settings: Settings) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((settings.host, settings.port), build_handler(settings))


def main() -> None:
    configure_logging()
    settings = Settings.from_env()
    server = create_server(settings)
    logging.info(
        json.dumps(
            {
                "timestamp": utc_now(),
                "service": settings.service_name,
                "environment": settings.environment,
                "message": "server started",
                "host": settings.host,
                "port": settings.port,
            },
            separators=(",", ":"),
        )
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info(json.dumps({"timestamp": utc_now(), "message": "server stopped"}))
    finally:
        server.server_close()
