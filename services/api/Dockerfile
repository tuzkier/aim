FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

COPY services/api/pyproject.toml services/api/uv.lock ./
COPY services/api/src ./src
RUN pip install --no-cache-dir --disable-pip-version-check .

COPY services/api/alembic.ini ./
COPY services/api/migrations ./migrations
COPY services/api/scripts ./scripts
COPY content ./content

EXPOSE 8000

CMD ["sh", "-c", "alembic upgrade head && exec uvicorn aim_api.main:app --host 0.0.0.0 --port 8000"]
