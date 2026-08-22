from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _headers(account_id, family_id, pregnancy_id, call_id="k1"):
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-knowledge-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    phone = "138" + str(int(UUID(account_id)) % 10**8).zfill(8)
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post("/api/v1/families", headers=public,
                         json={"name": "知识家庭", "role": "mother"}).json()
    pregnancy = client.post(f"/api/v1/families/{family['id']}/pregnancies",
                            headers=public, json={"due_date": "2027-01-12"}).json()
    return account_id, family["id"], pregnancy["id"], public


class TestKnowledgeTool:
    def test_writing_knowledge_requires_approval_first(self) -> None:
        """知识条目走「执行前确认」档：内容长、且常是模型总结出来的，
        先让用户看一眼再存。与建待办的直接执行档相对。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, _ = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-knowledge",
                headers=_headers(account_id, family_id, pregnancy_id, call_id="k0"),
                json={"title": "菠菜猪肝汤", "category": "nutrition", "form": "recipe",
                      "ingredients": ["菠菜"], "steps": ["煮"]},
            )

            assert response.status_code == 409
            assert response.json()["error"]["code"] == "approval_required"

    def test_a_recipe_written_by_the_agent_is_readable(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-knowledge",
                headers=_headers(account_id, family_id, pregnancy_id),
                json={
                    "title": "菠菜猪肝汤",
                    "category": "nutrition",
                    "form": "recipe",
                    "ingredients": ["菠菜 200g", "猪肝 100g"],
                    "steps": ["猪肝切片焯水", "下菠菜煮 3 分钟"],
                    "approved": True,
                },
            )
            assert response.status_code == 200, response.text

            records = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
            ).json()["records"]
            entry = next(r for r in records if r["type"] == "knowledge")
            assert entry["title"] == "菠菜猪肝汤"
            assert entry["structured_data"]["form"] == "recipe"

    def test_an_invalid_recipe_is_rejected_rather_than_stored_half_formed(self) -> None:
        """模型漏填做法时要挡住——一条只有食材的菜谱对用户没有价值。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, _ = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-knowledge",
                headers=_headers(account_id, family_id, pregnancy_id, call_id="k2"),
                json={"title": "半成品", "category": "nutrition", "form": "recipe",
                      "ingredients": ["菠菜"], "approved": True},
            )

            assert response.status_code in (409, 422), response.text
