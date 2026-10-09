from __future__ import annotations

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app


def test_weekly_content_covers_weeks_4_to_42() -> None:
    with TestClient(create_app()) as client:
        response = client.get("/api/v1/content/weekly")
    assert response.status_code == 200, response.text
    body = response.json()
    weeks = body["weeks"]
    assert [w["week"] for w in weeks] == list(range(4, 43))
    for w in weeks:
        assert w["fruit"] and w["fruit_name"] and w["baby"] and w["mom"], w["week"]
        assert 1 <= len(w["tips"]) <= 3, w["week"]
        assert w["length_cm"] is None or w["length_cm"] > 0
        assert w["weight_g"] is None or w["weight_g"] > 0
    assert body["reviewed_at"] and body["source"] and body["source_url"]


def test_sizes_grow_week_by_week() -> None:
    with TestClient(create_app()) as client:
        weeks = client.get("/api/v1/content/weekly").json()["weeks"]
    lengths = [w["length_cm"] for w in weeks if w["length_cm"] is not None]
    weights = [w["weight_g"] for w in weeks if w["weight_g"] is not None]
    assert lengths == sorted(lengths)
    assert weights == sorted(weights)
