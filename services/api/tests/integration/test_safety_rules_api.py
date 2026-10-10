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


def test_safety_rules_can_be_filtered_by_week() -> None:
    """按孕周过滤：34 周不该再看到宫外孕信号；不带参数时保持旧版 App 拿到的全部条目。"""
    with TestClient(create_app()) as client:
        all_items = client.get("/api/v1/safety-rules").json()["items"]
        late = client.get("/api/v1/safety-rules", params={"week": 34})

        assert late.status_code == 200, late.text
        late_ids = {item["id"] for item in late.json()["items"]}
        all_ids = {item["id"] for item in all_items}
        assert "ectopic-signs" not in late_ids
        assert "ectopic-signs" in all_ids
        assert late_ids < all_ids
        assert len(all_items) >= 16


def test_safety_rule_items_expose_weeks() -> None:
    with TestClient(create_app()) as client:
        items = client.get("/api/v1/safety-rules").json()["items"]

        assert all("weeks" in item for item in items)
        by_id = {item["id"]: item for item in items}
        assert by_id["ectopic-signs"]["weeks"] == [4, 13]
        assert by_id["urgent-bleeding"]["weeks"] is None


def test_safety_rules_reject_out_of_range_week() -> None:
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/safety-rules", params={"week": 99}).status_code == 422
