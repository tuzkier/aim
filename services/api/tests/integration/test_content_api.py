from __future__ import annotations

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app


def test_content_collection_is_readable() -> None:
    with TestClient(create_app()) as client:
        response = client.get("/api/v1/content/preparation")

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["items"]
        assert {"id", "title", "summary"} <= set(body["items"][0])


def test_unknown_collection_returns_404_rather_than_reading_disk() -> None:
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/content/pregnancy-tasks").status_code == 404
        assert client.get("/api/v1/content/nope").status_code == 404
