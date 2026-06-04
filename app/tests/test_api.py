from __future__ import annotations

import json
from pathlib import Path
import sys
from threading import Thread
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from zerotrust_demo.config import Settings
from zerotrust_demo.main import CONTROL_EVIDENCE, create_server


class ApiTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        settings = Settings(environment="test", host="127.0.0.1", port=0)
        cls.server = create_server(settings)
        cls.thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        host, port = cls.server.server_address
        cls.base_url = f"http://{host}:{port}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def request_json(self, path: str, method: str = "GET", payload: dict[str, str] | None = None):
        data = None
        headers = {"X-Request-ID": "unit-test-request"}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = Request(f"{self.base_url}{path}", data=data, headers=headers, method=method)
        with urlopen(request, timeout=5) as response:
            body = json.loads(response.read().decode("utf-8"))
            return response.status, dict(response.headers), body

    def test_health_endpoint_returns_security_headers(self) -> None:
        status, headers, body = self.request_json("/healthz")

        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "ok")
        self.assertEqual(body["environment"], "test")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(headers["X-Frame-Options"], "DENY")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Server"], "ZeroTrustDemo/1.0")

    def test_readiness_endpoint_reports_internal_checks(self) -> None:
        status, _, body = self.request_json("/readyz")

        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "ready")
        self.assertGreaterEqual(len(body["checks"]), 3)

    def test_posture_endpoint_returns_zero_trust_controls(self) -> None:
        status, _, body = self.request_json("/api/v1/posture")

        self.assertEqual(status, 200)
        self.assertEqual(body["controls"], CONTROL_EVIDENCE)
        self.assertIn("identity", {control["pillar"] for control in body["controls"]})

    def test_security_event_endpoint_accepts_valid_event(self) -> None:
        status, _, body = self.request_json(
            "/api/v1/events/security",
            method="POST",
            payload={
                "eventType": "privilege.change",
                "severity": "High",
                "accountName": "analyst@example.com",
                "ipAddress": "203.0.113.10",
            },
        )

        self.assertEqual(status, 202)
        self.assertEqual(body["status"], "accepted")
        self.assertEqual(body["classification"]["severity"], "High")
        self.assertEqual(body["routing"], "sentinel")

    def test_security_event_endpoint_rejects_unknown_event_type(self) -> None:
        with self.assertRaises(HTTPError) as error_context:
            self.request_json(
                "/api/v1/events/security",
                method="POST",
                payload={"eventType": "unknown", "severity": "High"},
            )

        self.assertEqual(error_context.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
