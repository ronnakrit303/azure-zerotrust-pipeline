# App Source

This directory contains the dependency-light Python demo API used as the
application target for CI security gates and container scanning.

## Package Layout

- `zerotrust_demo/main.py`: stdlib HTTP server, security headers, JSON logging,
  health/readiness/posture endpoints, and security event validation.
- `zerotrust_demo/config.py`: non-secret environment variable parsing.
- `zerotrust_demo/__main__.py`: module entry point for `python -m zerotrust_demo`.
- `zerotrust_demo/__init__.py`: package metadata.

## Runtime Settings

The app reads only non-secret configuration from environment variables:

- `APP_SERVICE_NAME`
- `APP_ENV`
- `APP_VERSION`
- `APP_HOST`
- `APP_PORT`
- `APP_REQUIRE_HTTPS`
- `APP_MAX_BODY_BYTES`
