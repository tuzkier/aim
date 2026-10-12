from datetime import timedelta
from uuid import uuid4

from fastapi.testclient import TestClient
from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.business_time import beijing_today
from aim_api.platform.config.settings import get_settings


def test_postpartum_content_is_reachable_alongside_existing_content_routes():
    with TestClient(create_app()) as client:
        response = client.get("/api/v1/content/postpartum")
        assert response.status_code == 200, response.text
        assert response.json()["version"] == "postpartum-cn-2026-v1"
        assert any(item["days"] == 42 for item in response.json()["care"])
        assert client.get("/api/v1/content/weekly").status_code == 200
        assert client.get("/api/v1/content/preparation").status_code == 200


def test_baby_care_validates_ownership_dates_and_prevents_unsafe_birth_retraction():
    with TestClient(create_app()) as client:
        pid, headers = scope(client); path = f"/api/v1/pregnancies/{pid}"
        _, other_headers = scope(client)
        birthday = beijing_today() - timedelta(days=5)
        born = client.post(path + "/birth", headers=headers,
                          json={"birth_date": birthday.isoformat(), "babies": [{"name": "小豆"}]}).json()
        baby = born["babies"][0]["id"]
        occurred = (beijing_today() - timedelta(days=1)).isoformat() + "T12:00:00+08:00"
        def write(kind, data, time=occurred):
            return client.post(path + "/records", headers=headers,
                json={"type": kind, "occurred_at": time, "visibility": "family", "structured_data": {"baby_id": baby, **data}})
        feeding = write("feeding", {"mode": "formula", "volume_ml": 60.5})
        assert feeding.status_code == 201, feeding.text
        diaper = write("diaper", {"kind": "both"})
        assert diaper.status_code == 201, diaper.text
        sleep = write("sleep", {"ended_at": (beijing_today() - timedelta(days=1)).isoformat() + "T14:00:00+08:00", "duration_seconds": 9999})
        assert sleep.status_code == 201, sleep.text
        assert sleep.json()["structured_data"]["duration_seconds"] == 7200
        assert write("feeding", {"mode": "unknown"}, (birthday - timedelta(days=1)).isoformat() + "T12:00:00+08:00").status_code == 409
        assert write("diaper", {"baby_id": str(uuid4()), "kind": "wet"}).status_code == 403
        assert client.get(path + "/babies", headers=other_headers).status_code == 403
        assert client.delete(path + "/birth", headers=headers).status_code == 409
        # 日期不能向后移到已有照护事实之后，修改失败不会改掉原生日。
        moved = client.patch(path + "/birth", headers=headers, json={"birth_date": beijing_today().isoformat()})
        assert moved.status_code == 409
        assert client.get(path + "/babies", headers=headers).json()["babies"][0]["birth_date"] == birthday.isoformat()


def test_agent_context_and_baby_tools_use_authoritative_postpartum_scope():
    from aim_api.platform.config.settings import get_settings
    with TestClient(create_app()) as client:
        pid, public = scope(client); path = f"/api/v1/pregnancies/{pid}"
        born = client.post(path + "/birth", headers=public, json={"birth_date": beijing_today().isoformat(), "babies": [{"name": "小豆"}]}).json()
        baby = born["babies"][0]
        me = client.get("/api/v1/me", headers=public).json()
        service = {"Service-Authorization": "Bearer " + get_settings().agent_service_secret,
                   "Actor-Account-Id": me["account_id"], "Family-Id": me["family_id"], "Pregnancy-Id": pid,
                   "Eve-Session-Id": "postpartum-" + pid, "Idempotency-Key": "context"}
        context = client.post("/internal/agent-tools/get-pregnancy-context", headers=service, json={})
        assert context.status_code == 200, context.text
        assert context.json()["data"]["stage"] == "postpartum"
        assert context.json()["data"]["red_flags"] == []
        service["Idempotency-Key"] = "babies"
        result = client.post("/internal/agent-tools/list-babies", headers=service, json={"pregnancy_id": str(uuid4())})
        assert result.status_code == 200, result.text
        assert result.json()["data"]["babies"][0]["id"] == baby["id"]
        service["Idempotency-Key"] = "care"
        logged = client.post("/internal/agent-tools/create-record", headers=service,
            json={"record_type": "feeding", "visibility": "private", "structured_data": {"baby_id": baby["id"], "mode": "unknown", "volume_ml": 60.5}})
        assert logged.status_code == 200, logged.text
        record = client.get(path + "/records?type=feeding", headers=public).json()["records"][0]
        assert record["visibility"] == "private"


def scope(client):
    actor = uuid4(); phone = "138" + str(int(actor) % 10**8).zfill(8)
    headers = {"Authorization": "Bearer " + issue_session_token(actor, phone, get_settings().auth_secret)}
    family = client.post("/api/v1/families", headers=headers, json={"name": "产后家庭", "role": "mother"}).json()["id"]
    pid = client.post(f"/api/v1/families/{family}/pregnancies", headers=headers,
                      json={"due_date": (beijing_today() + timedelta(days=10)).isoformat()}).json()["id"]
    plan = client.post(f"/api/v1/pregnancies/{pid}/plan", headers=headers, json={"as_of": beijing_today().isoformat()})
    assert plan.status_code == 201, plan.text
    return pid, headers


def test_birth_is_atomic_idempotent_and_closes_templates_without_faking_completion():
    with TestClient(create_app()) as client:
        pid, headers = scope(client)
        path = f"/api/v1/pregnancies/{pid}"
        manual = client.post(path + "/tasks", headers=headers, json={"title": "按医生要求复查"})
        assert manual.status_code == 201
        old_plan = client.get(path + "/plan", headers=headers).json()
        body = {"birth_date": beijing_today().isoformat(), "babies": [{"name": "小豆", "sex": "unknown", "birth_weight_grams": 3200}]}
        born = client.post(path + "/birth", headers=headers, json=body)
        assert born.status_code == 200, born.text
        result = born.json()
        assert result["pregnancy"]["status"] == "postpartum"
        assert result["pregnancy"]["postpartum_days"] == 0
        assert len(result["babies"]) == 1
        again = client.post(path + "/birth", headers=headers, json=body)
        assert again.status_code == 200, again.text
        assert again.json()["babies"][0]["id"] == result["babies"][0]["id"]
        plan = client.get(path + "/plan", headers=headers).json()
        tasks = {task["id"]: task for task in plan["tasks"]}
        for task in old_plan["tasks"]:
            assert tasks[task["id"]]["status"] == ("cancelled" if task["source_type"] == "template" else "todo")
        postpartum = [t for t in plan["tasks"] if (t["source_id"] or "").startswith("postpartum.")]
        assert any("42" in t["title"] for t in postpartum)
        assert any("百白破" in t["title"] for t in postpartum)
        assert len({t["source_id"] for t in postpartum}) == len(postpartum)
        assert client.get(path + "/today", headers=headers).status_code == 200


def test_invalid_baby_rolls_back_the_whole_transition_and_cross_family_access_is_rejected():
    with TestClient(create_app()) as client:
        pid, headers = scope(client)
        stranger, other = scope(client)
        path = f"/api/v1/pregnancies/{pid}"
        response = client.post(path + "/birth", headers=headers,
            json={"birth_date": beijing_today().isoformat(), "babies": [{"name": "测试", "birth_date": (beijing_today() + timedelta(days=1)).isoformat()}]})
        assert response.status_code == 409
        pregnancy = client.get(path, headers=headers).json()
        assert pregnancy["birth_date"] is None
        assert client.get(path + "/babies", headers=headers).json()["babies"] == []
        assert client.post(path + "/birth", headers=other, json={"birth_date": beijing_today().isoformat()}).status_code == 403
        assert client.get(path + "/babies", headers=other).status_code == 403


def test_retraction_preserves_history_and_a_new_revision_can_generate_a_new_schedule():
    with TestClient(create_app()) as client:
        pid, headers = scope(client)
        path = f"/api/v1/pregnancies/{pid}"
        original = client.get(path + "/plan", headers=headers).json()["tasks"]
        body = {"birth_date": beijing_today().isoformat(), "babies": [{"name": "测试宝宝"}]}
        first = client.post(path + "/birth", headers=headers, json=body).json()
        withdrawn = client.delete(path + "/birth", headers=headers)
        assert withdrawn.status_code == 200, withdrawn.text
        assert withdrawn.json()["status"] == "active"
        assert client.get(path + "/babies", headers=headers).json()["babies"] == []
        tasks = {t["id"]: t for t in client.get(path + "/plan", headers=headers).json()["tasks"]}
        for task in original:
            assert tasks[task["id"]]["status"] == task["status"]
        reborn = client.post(path + "/birth", headers=headers, json=body)
        assert reborn.status_code == 200, reborn.text
        assert reborn.json()["pregnancy"]["birth_revision"] != first["pregnancy"]["birth_revision"]
        assert reborn.json()["babies"][0]["id"] != first["babies"][0]["id"]


def test_date_correction_preserves_user_appointments_and_reschedules_only_defaults():
    with TestClient(create_app()) as client:
        pid, headers = scope(client); path = f"/api/v1/pregnancies/{pid}"
        old = beijing_today() - timedelta(days=5)
        born = client.post(path + "/birth", headers=headers, json={"birth_date": old.isoformat()})
        assert born.status_code == 200, born.text
        tasks = client.get(path + "/plan", headers=headers).json()["tasks"]
        care = [t for t in tasks if (t["source_id"] or "").startswith("postpartum.")]
        appointment = care[0]
        changed = client.post(f"/api/v1/tasks/{appointment['id']}/delay", headers=headers,
                             json={"expected_version": appointment["version"], "due_at": "2027-01-01T01:00:00Z"})
        assert changed.status_code == 200, changed.text
        corrected = client.patch(path + "/birth", headers=headers, json={"birth_date": (old - timedelta(days=1)).isoformat()})
        assert corrected.status_code == 200, corrected.text
        after = {t["id"]: t for t in client.get(path + "/plan", headers=headers).json()["tasks"]}
        assert after[appointment["id"]]["due_at"] == changed.json()["due_at"]
        assert client.delete(path + "/birth", headers=headers).status_code == 409


def test_date_conflict_rolls_back_birth_and_baby_dates(monkeypatch):
    from aim_api.contexts.planning.adapters.outbound.persistence.repositories import SqlAlchemyPlanningRepository
    from aim_api.contexts.planning.domain.task_status import TaskVersionConflict
    with TestClient(create_app()) as client:
        pid, headers = scope(client); path = f"/api/v1/pregnancies/{pid}"
        old = beijing_today() - timedelta(days=3)
        client.post(path + "/birth", headers=headers, json={"birth_date": old.isoformat(), "babies": [{"name": "小豆"}]})
        before = client.get(path + "/plan", headers=headers).json()
        async def concurrent_change(*args):
            raise TaskVersionConflict("another family member changed the appointment")
        monkeypatch.setattr(SqlAlchemyPlanningRepository, "save_task_change", concurrent_change)
        result = client.patch(path + "/birth", headers=headers, json={"birth_date": (old - timedelta(days=1)).isoformat()})
        assert result.status_code == 409, result.text
        assert client.get(path, headers=headers).json()["birth_date"] == old.isoformat()
        assert client.get(path + "/babies", headers=headers).json()["babies"][0]["birth_date"] == old.isoformat()
        assert client.get(path + "/plan", headers=headers).json() == before


def test_profiles_and_care_keep_baby_identity_and_private_scope_through_edits_and_deletion():
    with TestClient(create_app()) as client:
        pid, author = scope(client); path = f"/api/v1/pregnancies/{pid}"
        family = client.get(path, headers=author).json()["family_id"]
        member_id = uuid4(); phone = "139" + str(int(member_id) % 10**8).zfill(8)
        member = {"Authorization": "Bearer " + issue_session_token(member_id, phone, get_settings().auth_secret)}
        invite = client.post(f"/api/v1/families/{family}/invitations", headers=author,
                             json={"invitee_phone": phone, "role": "father"}).json()
        assert client.post(f"/api/v1/family-invitations/{invite['token']}/accept", headers=member).status_code == 200
        birth = beijing_today() - timedelta(days=14)
        babies = client.post(path + "/birth", headers=author,
            json={"birth_date": birth.isoformat(), "babies": [{"name": "姐姐"}, {"name": "弟弟"}]}).json()["babies"]
        assert len({b["id"] for b in babies}) == 2
        first, second = babies
        profile = client.patch(path + "/babies/" + second["id"], headers=member,
            json={"name": "小豆", "birth_date": birth.isoformat(), "sex": "male", "birth_weight_grams": 3200})
        assert profile.status_code == 200, profile.text
        assert profile.json()["id"] == second["id"]
        time = (beijing_today() - timedelta(days=1)).isoformat() + "T12:00:00+08:00"
        saved = client.post(path + "/records", headers=author, json={"type": "feeding", "occurred_at": time,
            "visibility": "private", "structured_data": {"baby_id": first["id"], "mode": "unknown", "volume_ml": 60.5}})
        assert saved.status_code == 201, saved.text
        record_path = path + "/records/" + saved.json()["id"]
        assert client.get(path + "/records?type=feeding", headers=member).json()["records"] == []
        changed = client.patch(record_path, headers=author,
            json={"structured_data": {"baby_id": second["id"], "mode": "formula", "volume_ml": 90.5}})
        assert changed.status_code == 200, changed.text
        assert changed.json()["structured_data"]["baby_id"] == second["id"]
        assert client.get(record_path, headers=member).status_code == 404
        assert client.delete(record_path, headers=author).status_code == 204
        assert client.get(path + "/records?type=feeding", headers=author).json()["records"] == []
        # 删除可见日志仍保留真实审计事实，不能据此撤销分娩或把生日移到它之后。
        assert client.delete(path + "/birth", headers=author).status_code == 409
        assert client.patch(path + "/babies/" + second["id"], headers=author,
            json={"name": "小豆", "birth_date": beijing_today().isoformat()}).status_code == 409


def test_logging_in_after_birth_does_not_regenerate_prenatal_tasks_when_plan_is_empty():
    from aim_api.contexts.identity.adapters.inbound.http.router import _ensure_initial_plan
    with TestClient(create_app()) as client:
        pid, headers = scope(client); path = f"/api/v1/pregnancies/{pid}"
        actor = client.get("/api/v1/me", headers=headers).json()["account_id"]
        assert client.post(path + "/birth", headers=headers, json={"birth_date": beijing_today().isoformat()}).status_code == 200
        for task in client.get(path + "/plan", headers=headers).json()["tasks"]:
            assert client.delete(path + "/tasks/" + task["id"], headers=headers).status_code == 204
        from uuid import UUID
        client.portal.call(_ensure_initial_plan, UUID(pid), UUID(actor), client.app.state.database)
        assert client.get(path + "/plan", headers=headers).json()["tasks"] == []
