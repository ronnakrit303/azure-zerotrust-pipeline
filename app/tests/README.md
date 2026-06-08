# App Tests

This directory contains unit tests for the demo API and configuration loader.
The tests run with Python's standard `unittest` framework so the container build
does not need third-party test dependencies.

## Coverage

- Health, readiness, and posture endpoint behavior.
- Security response headers.
- Accepted and rejected security event payloads.
- Non-secret environment variable parsing and fallback behavior.

Run from the repository root:

```powershell
python -X utf8 -m unittest discover -s app\tests -v
```
