from __future__ import annotations

from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from zerotrust_demo.config import Settings


class SettingsTestCase(unittest.TestCase):
    def test_settings_from_env_uses_non_secret_values(self) -> None:
        with patch.dict(
            "os.environ",
            {
                "APP_SERVICE_NAME": "demo",
                "APP_ENV": "test",
                "APP_VERSION": "9.9.9",
                "APP_HOST": "127.0.0.1",
                "APP_PORT": "9090",
                "APP_REQUIRE_HTTPS": "true",
                "APP_MAX_BODY_BYTES": "128",
            },
            clear=True,
        ):
            settings = Settings.from_env()

        self.assertEqual(settings.service_name, "demo")
        self.assertEqual(settings.environment, "test")
        self.assertEqual(settings.version, "9.9.9")
        self.assertEqual(settings.host, "127.0.0.1")
        self.assertEqual(settings.port, 9090)
        self.assertTrue(settings.require_https)
        self.assertEqual(settings.max_body_bytes, 128)

    def test_invalid_numeric_env_values_fall_back_to_defaults(self) -> None:
        with patch.dict("os.environ", {"APP_PORT": "not-a-number", "APP_MAX_BODY_BYTES": "-1"}, clear=True):
            settings = Settings.from_env()

        self.assertEqual(settings.port, 8080)
        self.assertEqual(settings.max_body_bytes, 8192)


if __name__ == "__main__":
    unittest.main()
