from __future__ import annotations

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app


def test_safety_rules_are_publicly_readable() -> None:
    """危险信号是安全兜底内容，不含个人数据，不该要求登录——
    真出事的时候不该被登录态挡住。"""
    with TestClient(create_app()) as client:
        response = client.get("/api/v1/safety-rules")

        assert response.status_code == 200, response.text
        items = response.json()["items"]
        assert items
        assert items[0]["severity"] == "urgent"
        assert {"id", "condition", "action", "severity", "source_url"} <= set(items[0])
