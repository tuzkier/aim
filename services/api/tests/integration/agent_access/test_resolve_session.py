from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _service_headers() -> dict[str, str]:
    return {"Service-Authorization": f"Bearer {get_settings().agent_service_secret}"}


def _scope(client: TestClient) -> tuple[str, str, str, str]:
    account_id = str(uuid4())
    phone = _phone(account_id)
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "Agent 家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": "2027-01-12"},
    ).json()
    return account_id, token, family["id"], pregnancy["id"]


class TestResolveSession:
    """Agent 运行时不持有 `AUTH_SECRET`，身份要来这里换。

    换出来的 scope 必须完全由服务端按账号查出，调用方自报的一概不作数——
    运行时那个通道是对公网暴露的。
    """

    def test_a_valid_token_resolves_to_the_accounts_own_scope(self) -> None:
        with TestClient(create_app()) as client:
            account_id, token, family_id, pregnancy_id = _scope(client)

            response = client.post(
                f"{GATEWAY}/resolve-session",
                headers=_service_headers(),
                json={"token": token},
            )

            assert response.status_code == 200, response.text
            assert response.json() == {
                "account_id": account_id,
                "family_id": family_id,
                "pregnancy_id": pregnancy_id,
            }

    def test_a_forged_token_is_rejected(self) -> None:
        """签名对不上就没有身份可言。"""
        with TestClient(create_app()) as client:
            _scope(client)

            response = client.post(
                f"{GATEWAY}/resolve-session",
                headers=_service_headers(),
                json={"token": "aim.v1.eyJhIjoxfQ.deadbeef"},
            )

            assert response.status_code == 401

    def test_a_garbage_token_is_rejected(self) -> None:
        with TestClient(create_app()) as client:
            response = client.post(
                f"{GATEWAY}/resolve-session",
                headers=_service_headers(),
                json={"token": "这不是一个有效的token"},
            )

            assert response.status_code == 401

    def test_the_endpoint_itself_requires_the_service_credential(self) -> None:
        """没有服务凭据的调用方不能拿这个端点当 token 解析器用。"""
        with TestClient(create_app()) as client:
            _, token, _, _ = _scope(client)

            response = client.post(
                f"{GATEWAY}/resolve-session",
                headers={"Service-Authorization": "Bearer a-guess"},
                json={"token": token},
            )

            assert response.status_code == 401
