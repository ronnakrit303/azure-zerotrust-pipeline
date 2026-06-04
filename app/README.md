# Zero Trust Demo App

Small Python HTTP API used as the application target for the DevSecOps pipeline.
It has no third-party runtime dependencies, emits structured JSON logs to stdout,
adds security headers, and exposes health/readiness/posture endpoints.

## Local Run

```bash
cd app
PYTHONPATH=src python -m zerotrust_demo
```

Endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/posture`
- `POST /api/v1/events/security`

## Tests

```bash
cd app
PYTHONPATH=src python -m unittest discover -s tests -v
```

## Container

```bash
docker build --tag azure-zerotrust-demo:local app
docker run --rm -p 8080:8080 azure-zerotrust-demo:local
```
