FROM python:3.12-alpine AS test

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

COPY src ./src
COPY tests ./tests

RUN python -m unittest discover -s tests -v

FROM python:3.12-alpine AS runtime

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    APP_ENV=prod \
    APP_HOST=0.0.0.0 \
    APP_PORT=8080

RUN addgroup -S app && \
    adduser -S -G app -h /app app

COPY --from=test /app/src ./src

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; r = urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2); raise SystemExit(0 if r.status == 200 else 1)"

CMD ["python", "-m", "zerotrust_demo"]
