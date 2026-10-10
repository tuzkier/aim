from concurrent.futures import ThreadPoolExecutor
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def scope(client):
    account = str(uuid4())
    phone = "136" + str(int(UUID(account)) % 10**8).zfill(8)
    public = {"Authorization": "Bearer " + issue_session_token(
        UUID(account), phone, get_settings().auth_secret)}
    family = client.post("/api/v1/families", headers=public,
                         json={"name": "记忆家庭", "role": "mother"}).json()["id"]
    pregnancy = client.post(f"/api/v1/families/{family}/pregnancies", headers=public,
                            json={"due_date": "2027-01-12"}).json()["id"]
    return account, family, pregnancy, public


def internal(s, key=None):
    account, family, pregnancy, _ = s
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account, "Family-Id": family, "Pregnancy-Id": pregnancy,
        "Eve-Session-Id": f"memory-{account}", "Idempotency-Key": key or str(uuid4()),
    }


def create(client, s, text="回答请简短", visibility="family"):
    return client.post(f"/api/v1/pregnancies/{s[2]}/records", headers=s[3], json={
        "type": "memory", "visibility": visibility, "occurred_at": "2026-10-10T09:00:00+08:00",
        "structured_data": {"kind": "preference", "text": text},
    })


def test_memory_direct_execution_idempotency_and_undo():
    with TestClient(create_app()) as client:
        s = scope(client)
        headers = internal(s, "remember-once")
        body = {"kind": "preference", "text": "回答请简短"}
        one = client.post("/internal/agent-tools/remember", headers=headers, json=body)
        assert one.status_code == 200, one.text
        two = client.post("/internal/agent-tools/remember", headers=headers, json=body)
        assert one.json() == two.json()
        memories = client.post("/internal/agent-tools/list-memories", headers=internal(s), json={})
        assert memories.status_code == 200, memories.text
        assert len(memories.json()["data"]["records"]) == 1
        undone = client.post("/internal/agent-tools/undo-operation", headers=internal(s), json={
            "operation_id": one.json()["operation_id"],
        })
        assert undone.status_code == 200, undone.text
        assert client.post("/internal/agent-tools/list-memories", headers=internal(s),
                           json={}).json()["data"]["records"] == []


def test_forget_needs_confirmation_and_can_only_delete_memories():
    with TestClient(create_app()) as client:
        s = scope(client)
        record = create(client, s).json()
        denied = client.post("/internal/agent-tools/forget-memory", headers=internal(s),
                             json={"id": record["id"]})
        assert denied.status_code == 409
        assert denied.json()["error"]["code"] == "approval_required"
        assert client.get(f"/api/v1/pregnancies/{s[2]}/records/{record['id']}",
                          headers=s[3]).status_code == 200
        forgotten = client.post("/internal/agent-tools/forget-memory", headers=internal(s),
                                json={"id": record["id"], "approved": True})
        assert forgotten.status_code == 200, forgotten.text
        note = client.post(f"/api/v1/pregnancies/{s[2]}/records", headers=s[3], json={
            "type": "note", "visibility": "family", "occurred_at": "2026-10-10T09:00:00Z",
            "content": "普通笔记", "structured_data": {},
        }).json()
        other = client.post("/internal/agent-tools/forget-memory", headers=internal(s),
                            json={"id": note["id"], "approved": True})
        assert other.status_code == 409
        assert client.get(f"/api/v1/pregnancies/{s[2]}/records/{note['id']}",
                          headers=s[3]).status_code == 200


def test_edit_replaces_the_fact_and_delete_frees_a_slot():
    with TestClient(create_app()) as client:
        s = scope(client)
        for i in range(50):
            response = create(client, s, f"偏好 {i}", "private")
            assert response.status_code == 201, response.text
        assert create(client, s).status_code == 409
        record = response.json()
        path = f"/api/v1/pregnancies/{s[2]}/records/{record['id']}"
        updated = client.patch(path, headers=s[3], json={
            "structured_data": {"kind": "care", "text": "  换到市一医院  "}, "title": "旧标题",
        })
        assert updated.status_code == 200, updated.text
        assert updated.json()["title"] == "换到市一医院"
        assert client.delete(path, headers=s[3]).status_code == 204
        assert create(client, s).status_code == 201


def test_concurrent_creation_cannot_exceed_fifty():
    with TestClient(create_app()) as client:
        s = scope(client)
        for i in range(49):
            assert create(client, s, f"偏好 {i}").status_code == 201
        with ThreadPoolExecutor(max_workers=2) as workers:
            codes = list(workers.map(lambda i: create(client, s, f"并发 {i}").status_code, [1, 2]))
        assert sorted(codes) == [201, 409]


def test_cross_family_access_cannot_read_or_forget_memories():
    with TestClient(create_app()) as client:
        owner, outsider = scope(client), scope(client)
        record = create(client, owner, visibility="private").json()
        headers = internal((outsider[0], owner[1], owner[2], outsider[3]))
        assert client.post("/internal/agent-tools/list-memories", headers=headers,
                           json={}).status_code == 403
        assert client.post("/internal/agent-tools/forget-memory", headers=headers,
                           json={"id": record["id"], "approved": True}).status_code == 403


def test_family_member_only_reads_shared_memories_and_cannot_hide_them():
    with TestClient(create_app()) as client:
        owner = scope(client)
        account = str(uuid4())
        phone = "139" + str(int(UUID(account)) % 10**8).zfill(8)
        public = {"Authorization": "Bearer " + issue_session_token(
            UUID(account), phone, get_settings().auth_secret)}
        invite = client.post(f"/api/v1/families/{owner[1]}/invitations", headers=owner[3],
                             json={"invitee_phone": phone, "role": "father"})
        accepted = client.post(
            f"/api/v1/family-invitations/{invite.json()['token']}/accept", headers=public)
        assert accepted.status_code == 200, accepted.text
        member = (account, owner[1], owner[2], public)
        shared = create(client, owner, "共享偏好").json()
        private = create(client, owner, "私有偏好", "private").json()
        records = client.post("/internal/agent-tools/list-memories", headers=internal(member),
                              json={}).json()["data"]["records"]
        assert [r["id"] for r in records] == [shared["id"]]
        assert records[0]["author_account_id"] == owner[0]
        path = f"/api/v1/pregnancies/{owner[2]}/records/{shared['id']}"
        assert client.patch(path, headers=public, json={"visibility": "private"}).status_code == 403
        edited = client.patch(path, headers=public, json={
            "structured_data": {"kind": "preference", "text": "家人更新共享偏好"},
        })
        assert edited.status_code == 200, edited.text
        assert edited.json()["title"] == "家人更新共享偏好"
        hidden = client.post("/internal/agent-tools/forget-memory", headers=internal(member),
                             json={"id": private["id"], "approved": True})
        assert hidden.status_code == 409
        assert client.get(f"/api/v1/pregnancies/{owner[2]}/records/{private['id']}",
                          headers=owner[3]).status_code == 200
