"""Application settings loaded from non-secret environment variables."""

from __future__ import annotations

from dataclasses import dataclass
import os

from zerotrust_demo import __version__


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _as_int(value: str | None, default: int) -> int:
    if value is None:
        return default
    try:
        parsed = int(value)
    except ValueError:
        return default
    return parsed if parsed > 0 else default


@dataclass(frozen=True)
class Settings:
    service_name: str = "zero-trust-demo-api"
    environment: str = "dev"
    version: str = __version__
    host: str = "0.0.0.0"
    port: int = 8080
    require_https: bool = False
    max_body_bytes: int = 8192

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            service_name=os.getenv("APP_SERVICE_NAME", cls.service_name),
            environment=os.getenv("APP_ENV", cls.environment),
            version=os.getenv("APP_VERSION", cls.version),
            host=os.getenv("APP_HOST", cls.host),
            port=_as_int(os.getenv("APP_PORT"), cls.port),
            require_https=_as_bool(os.getenv("APP_REQUIRE_HTTPS"), cls.require_https),
            max_body_bytes=_as_int(os.getenv("APP_MAX_BODY_BYTES"), cls.max_body_bytes),
        )

    def public_metadata(self) -> dict[str, str | int | bool]:
        return {
            "service": self.service_name,
            "environment": self.environment,
            "version": self.version,
            "requireHttps": self.require_https,
        }
