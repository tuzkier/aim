FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

# 可覆盖的 pip 源：默认官方源，本地开发行为不变；
# 国内服务器构建时用 --build-arg PIP_INDEX_URL=... 指向镜像站
ARG PIP_INDEX_URL=https://pypi.org/simple
ARG PIP_TRUSTED_HOST=pypi.org
ENV PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST}

COPY services/api/pyproject.toml services/api/uv.lock ./
COPY services/api/src ./src
RUN pip install --no-cache-dir --disable-pip-version-check .

COPY services/api/alembic.ini ./
COPY services/api/migrations ./migrations
COPY services/api/scripts ./scripts
COPY content ./content

EXPOSE 8000

CMD ["sh", "-c", "alembic upgrade head && exec uvicorn aim_api.main:app --host 0.0.0.0 --port 8000"]
