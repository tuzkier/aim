# Pregnancy Records Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a first-class pregnancy records experience to Aim so users can capture symptoms, checkups, and notes, share them with family according to visibility, and explicitly turn a record into a plan task.

**Architecture:** Add a standalone `records` bounded context in the FastAPI DDD structure, with its own domain model, application commands/queries, PostgreSQL persistence, and HTTP router. Reuse the existing planning task lifecycle for the explicit “turn into task” action, adding a `record` task source. Add a read-only Agent tool for scoped record retrieval, then expose the workflow through a new native iOS Records tab.

**Tech Stack:** Python 3.13, FastAPI, Pydantic, SQLAlchemy async, Alembic, PostgreSQL, Eve/TypeScript tools, SwiftUI, URLSession, XCTest, XCUITest.

---

### Task 1: Create the records domain and persistence schema

**Files:**
- Create: `services/api/src/aim_api/contexts/records/__init__.py`
- Create: `services/api/src/aim_api/contexts/records/domain/record.py`
- Create: `services/api/src/aim_api/contexts/records/domain/errors.py`
- Create: `services/api/src/aim_api/contexts/records/application/ports.py`
- Create: `services/api/src/aim_api/contexts/records/adapters/outbound/persistence/models.py`
- Create: `services/api/src/aim_api/contexts/records/adapters/outbound/persistence/repositories.py`
- Create: `services/api/migrations/versions/0004_records.py`
- Modify: `services/api/src/aim_api/contexts/planning/domain/task.py`
- Test: `services/api/tests/domain/records/test_record.py`
- Test: `services/api/tests/domain/planning/test_task_lifecycle.py`

**Step 1: Write failing domain tests**

Add tests for creation, type-specific payload validation, author-only mutation, soft deletion, and `TaskSourceType.record`:

```python
def test_record_create_validates_type_specific_payload():
    record = Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.symptom,
        occurred_at=now,
        visibility=RecordVisibility.family,
        structured_data={"symptoms": ["nausea"], "severity": 3, "note": "早晨明显"},
    )
    assert record.record_type is RecordType.symptom

def test_record_rejects_invalid_symptom_severity():
    with pytest.raises(RecordValidationError):
        make_record(record_type=RecordType.symptom, structured_data={"severity": 6})

def test_only_author_can_edit_or_soft_delete_record():
    record = make_record(author_account_id=author_id)
    record.assert_can_mutate(author_id)
    with pytest.raises(RecordAccessDenied):
        record.assert_can_mutate(other_account_id)

def test_record_task_source_type_is_supported():
    assert TaskSourceType.record.value == "record"
```

Run from `services/api`:

```bash
DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' python3 -m pytest -q tests/domain/records tests/domain/planning/test_task_lifecycle.py
```

Expected: FAIL because the records context, validation errors, and `TaskSourceType.record` do not exist.

**Step 2: Implement the domain**

Implement `RecordType` (`symptom`, `checkup`, `note`), `RecordVisibility` (`family`, `private`), record creation, type-specific payload validation, author mutation guard, soft-delete state, and records domain errors. Keep `structured_data` as a JSON object and do not put Agent-inferred values into it:

- symptom: `symptoms` is a non-empty string list, `severity` is an integer from 1 through 5, and `note` is optional;
- checkup: `hospital`, `exam_items`, `result`, and `doctor_advice` are strings;
- note: title is optional and content is non-empty.

Keep `attachment_refs` as an empty/reserved list field; no upload behavior is implemented.

Add SQLAlchemy `RecordModel` with `id`, `pregnancy_id`, `family_id`, `author_account_id`, `record_type`, `occurred_at`, `visibility`, `title`, `content`, `structured_data`, `attachment_refs`, `created_at`, `updated_at`, and nullable `deleted_at`. Add indexes for `(pregnancy_id, occurred_at)` and `(family_id, visibility)`.

Add a repository that maps models to domain records, adds records, gets a visible record, lists visible records with optional type/date filters, saves updates, and soft-deletes. Add a records unit-of-work protocol with family membership and pregnancy ownership ports, matching existing contexts.

Create Alembic revision `0004_records` with `down_revision = "0003_planning"`. Use PostgreSQL UUID/JSON/DateTime types and make downgrade drop the indexes and table.

**Step 3: Run the domain tests**

Run the same pytest command. Expected: PASS for the new records tests and existing planning tests.

**Step 4: Commit**

```bash
git add services/api/src/aim_api/contexts/records services/api/src/aim_api/contexts/planning/domain/task.py services/api/migrations/versions/0004_records.py services/api/tests/domain/records services/api/tests/domain/planning/test_task_lifecycle.py
git commit -m "feat(records): add record domain and persistence schema"
```

### Task 2: Add record commands, queries, and authenticated HTTP API

**Files:**
- Create: `services/api/src/aim_api/contexts/records/application/commands/create_record.py`
- Create: `services/api/src/aim_api/contexts/records/application/commands/update_record.py`
- Create: `services/api/src/aim_api/contexts/records/application/commands/delete_record.py`
- Create: `services/api/src/aim_api/contexts/records/application/queries/list_records.py`
- Create: `services/api/src/aim_api/contexts/records/application/queries/get_record.py`
- Create: `services/api/src/aim_api/contexts/records/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/bootstrap.py`
- Test: `services/api/tests/integration/records/test_records_api.py`
- Test: `services/api/tests/contract/test_openapi_snapshots.py`

**Step 1: Write failing API tests**

Create random demo accounts and pregnancies. Cover creation of all three types, type validation, newest-first ordering, type filtering, get/edit/soft-delete, family visibility, private visibility, non-author mutation rejection, and cross-family rejection. Use a request such as:

```python
response = client.post(
    f"/api/v1/pregnancies/{pregnancy_id}/records",
    headers=headers,
    json={
        "type": "symptom",
        "occurred_at": "2026-08-16T08:30:00+08:00",
        "visibility": "family",
        "structured_data": {"symptoms": ["nausea"], "severity": 3, "note": "早晨明显"},
    },
)
assert response.status_code == 201
```

Run:

```bash
DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' python3 -m pytest -q tests/integration/records/test_records_api.py
```

Expected: FAIL because the router and endpoints do not exist.

**Step 2: Implement commands, queries, and router**

Commands verify active family membership and pregnancy ownership. Create derives family and author IDs from the authenticated actor; clients cannot override either. Update and delete load through the visibility-aware repository and enforce author-only mutation. List and get use the same visibility filter so private records cannot be inferred by status differences.

Add Pydantic request/response models:

- `CreateRecordRequest(type, occurred_at, visibility, title, content, structured_data)`;
- `UpdateRecordRequest(occurred_at, visibility, title, content, structured_data)`;
- `RecordResponse` with all public fields and `attachment_refs`;
- `RecordListResponse` with `records`.

Expose:

- `POST /api/v1/pregnancies/{pregnancy_id}/records` (201);
- `GET /api/v1/pregnancies/{pregnancy_id}/records` with optional `type`;
- `GET /api/v1/pregnancies/{pregnancy_id}/records/{record_id}`;
- `PATCH /api/v1/pregnancies/{pregnancy_id}/records/{record_id}`;
- `DELETE /api/v1/pregnancies/{pregnancy_id}/records/{record_id}` (204).

Translate records access, validation, not-found, and conflict errors using existing `ApiError` handlers. Include the router in `create_app`; every endpoint must authenticate.

**Step 3: Run API tests and export the contract**

```bash
DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' python3 -m pytest -q tests/integration/records/test_records_api.py tests/contract
PYTHONPATH=src python3 scripts/export_contracts.py
```

Expected: targeted tests pass and `contracts/public-api/openapi.json` contains the records operations.

**Step 4: Commit**

```bash
git add services/api/src/aim_api/contexts/records/application services/api/src/aim_api/contexts/records/adapters/inbound/http/router.py services/api/src/aim_api/bootstrap.py services/api/tests/integration/records services/api/tests/contract contracts/public-api/openapi.json
git commit -m "feat(records): expose authenticated record API"
```

### Task 3: Add explicit record-to-task creation

**Files:**
- Create: `services/api/src/aim_api/contexts/planning/application/commands/create_task.py`
- Modify: `services/api/src/aim_api/contexts/planning/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/contexts/planning/domain/errors.py`
- Test: `services/api/tests/application/planning/test_commands.py`
- Test: `services/api/tests/integration/records/test_records_api.py`

**Step 1: Write failing command and endpoint tests**

Add a command test that creates a task in an existing pregnancy plan with `source_type=TaskSourceType.record`, `source_id` equal to the record ID, `changed_by_actor_type=ActorType.account`, and the requested due date. Add an integration test that creates a record, posts `POST /api/v1/pregnancies/{pregnancy_id}/tasks` with `record_id`, `title`, `description`, and optional `due_at`, and asserts source metadata and cross-family rejection.

Run the targeted tests and expect failure because no generic task creation command or endpoint exists.

**Step 2: Implement the command and route**

`CreateTaskCommand` verifies that the pregnancy belongs to the account's active family and that a plan exists. It creates a `Task` with `Task.create`, adds it through the planning repository, commits, and returns it. Add `CreateTaskRequest` with title, optional description/due date, optional source type/source ID, and optional assignee. For the record flow, validate the source record belongs to the same pregnancy before creating the task. Expose `POST /api/v1/pregnancies/{pregnancy_id}/tasks` and reuse `_task_response`.

**Step 3: Run tests**

```bash
DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' python3 -m pytest -q tests/application/planning/test_commands.py tests/integration/records/test_records_api.py
```

Expected: PASS.

**Step 4: Commit**

```bash
git add services/api/src/aim_api/contexts/planning/application/commands/create_task.py services/api/src/aim_api/contexts/planning/adapters/inbound/http/router.py services/api/src/aim_api/contexts/planning/domain/errors.py services/api/tests/application/planning/test_commands.py services/api/tests/integration/records/test_records_api.py
git commit -m "feat(planning): create tasks from records"
```

### Task 4: Give Agent a scoped, read-only records tool

**Files:**
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`
- Create: `services/agent/agent/tools/list_records.ts`
- Modify: `services/agent/tests/runtime-gate.test.ts`
- Create: `services/agent/tests/tools/records.test.ts`

**Step 1: Write failing tool tests**

Add a TypeScript test for `list_records` that stubs `fetch`, calls the tool with an Eve context, and asserts it sends only filters and no actor/family/pregnancy IDs in the body. Add an API agent-access test that calls the internal route with service authorization and verifies only records visible to the scoped account are returned.

Run `npm test` from `services/agent` and the targeted API agent-access tests. Expected: FAIL because the tool and internal endpoint do not exist.

**Step 2: Implement the internal route**

Add `ListRecordsRequest` with optional `type`, `from`, and `to`. Add `_list_records` to the agent-access router. Reuse `_run(..., write=False)` and the existing `AgentToolContext`; query records through the same visibility-aware application query as the public API. Return normalized records under `data.records` and a count summary. Do not add approval or any write path.

**Step 3: Implement the Eve tool and update manifest expectations**

Create `list_records.ts` with an optional Zod filter object and `callBusinessApi(ctx, "/internal/agent-tools/list-records", body)`. Update the compiled-tool expectation in `runtime-gate.test.ts` to include `list_records`, rebuild the Eve manifest, and assert the tool remains read-only.

**Step 4: Run tests and commit**

```bash
cd services/agent && npm run lint && npm test
cd ../api && DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' python3 -m pytest -q tests/integration/agent_access
```

Expected: TypeScript lint, Agent tests, and API agent-access tests pass.

```bash
git add services/api/src/aim_api/contexts/agent_access services/agent/agent/tools/list_records.ts services/agent/tests
git commit -m "feat(agent): read scoped pregnancy records"
```

### Task 5: Add iOS record models and repository operations

**Files:**
- Create: `apps/ios/AimApp/Features/Records/RecordModels.swift`
- Create: `apps/ios/AimApp/Features/Records/RecordStore.swift`
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`
- Modify: `apps/ios/AimApp/Generated/OpenAPI/Models.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`
- Test: `apps/ios/AimApp/Tests/BusinessRepositoryTests.swift`
- Test: `apps/ios/AimApp/Tests/RecordStoreTests.swift`

**Step 1: Write failing Swift model/store tests**

Add tests for decoding a symptom record with string-array symptoms and integer severity, decoding a checkup record, mapping unknown record types to `.unknown`, sorting preview records newest first, and preserving a draft when repository save fails.

Run:

```bash
DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer \
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug \
-destination 'platform=iOS Simulator,id=7ED7C4CE-46EC-42D0-B81B-F6C31D8CBD1F' \
-derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test
```

Expected: FAIL because record types, DTOs, and store do not exist.

**Step 2: Implement models and repository methods**

Add `RecordType`, `RecordVisibility`, typed `SymptomRecordData` and `CheckupRecordData`, `RecordItem`, `RecordDraft`, and `RecordSnapshot`. Add Codable API DTOs with `structured_data` fields; use typed structured-data DTOs instead of the existing string-only `AnyCodable`, while allowing unknown JSON fields to be ignored.

Extend `BusinessRepositoryProtocol` and `BusinessRepository` with `fetchRecords(type:)`, `createRecord(draft:)`, `updateRecord(recordID:draft:)`, `deleteRecord(recordID:)`, and `createTaskFromRecord(record:title:description:dueAt:)`. Each method uses the authenticated pregnancy ID and existing Aim date/JSON strategies.

Add the new Swift files and tests to the Xcode project sources/build phases.

**Step 3: Run Swift tests**

Run the same `xcodebuild ... test` command. Expected: the new tests and all existing tests pass.

**Step 4: Commit**

```bash
git add apps/ios/AimApp/Features/Records apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift apps/ios/AimApp/Generated/OpenAPI/Models.swift apps/ios/AimApp/Tests/RecordStoreTests.swift apps/ios/AimApp/Tests/BusinessRepositoryTests.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): add records data layer"
```

### Task 6: Build the native Records tab and record composer

**Files:**
- Create: `apps/ios/AimApp/Features/Records/RecordsView.swift`
- Create: `apps/ios/AimApp/Features/Records/RecordComposerView.swift`
- Create: `apps/ios/AimApp/Features/Records/RecordDetailView.swift`
- Modify: `apps/ios/AimApp/App/AimApp.swift`
- Modify: `apps/ios/AimApp/Features/Records/RecordStore.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`
- Test: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

**Step 1: Write the failing UI journey**

Extend the UI test to enter the demo account, select “记录”, open the empty-state action, choose “身体感受”, select a symptom and severity, select family visibility, save, assert the record appears, open it, and assert “转为待办” is present.

Run the simulator UI test and expect failure because the tab and controls do not exist.

**Step 2: Implement the Records tab**

Add `RecordsView` using the existing Aim warm background, inset-grouped lists, and navigation style. Distinguish loading, empty, error, and loaded states. Add type filters and a `+` toolbar button. Add `RecordStore.load`, `save`, `update`, and `remove`; failed writes keep the draft in the composer.

Add `RecordComposerView` as a sheet or pushed flow:

- type selection first;
- symptom form with tags, 1–5 severity, optional note, and occurred-at date;
- checkup form with date, hospital, exam items, result, and doctor advice;
- note form with title, body, and occurred-at date;
- shared/private picker and save button.

Add `RecordDetailView` with edit/delete/turn-into-task actions. Use a destructive confirmation dialog for delete. The task action presents a confirmation sheet, then calls `createTaskFromRecord` and refreshes record/plan state.

Add the fifth tab in `MainTabView` as `RecordsView`, place it between Plan and Family, label it “记录”, inject the same `BusinessRepository`, and reload it when the pregnancy changes. Add all new Swift files/tests to the Xcode project.

**Step 3: Run UI and unit tests**

```bash
DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer \
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug \
-destination 'platform=iOS Simulator,id=7ED7C4CE-46EC-42D0-B81B-F6C31D8CBD1F' \
-derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test
```

Expected: all Swift unit and UI tests pass.

**Step 4: Commit**

```bash
git add apps/ios/AimApp/Features/Records apps/ios/AimApp/App/AimApp.swift apps/ios/AimApp/UITests/CoreJourneyUITests.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): add pregnancy records workflow"
```

### Task 7: Verify, deploy, and perform simulator acceptance

**Files:**
- Modify only if verification exposes a defect; otherwise no source changes.

**Step 1: Run complete repository checks**

```bash
DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' make verify
DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer make ios-parse
```

Expected: API tests, Agent lint/tests, contract export, repository verification, and Swift parsing all pass.

**Step 2: Rebuild API and Agent services**

```bash
docker compose -f infrastructure/compose/compose.yaml up -d --build api eve
docker compose -f infrastructure/compose/compose.yaml ps
```

Expected: `api`, `eve`, and `postgres` are healthy; Alembic applies `0004_records`.

**Step 3: Build and install iOS**

```bash
DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer \
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -sdk iphonesimulator \
-configuration Debug -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer \
xcrun simctl install 7ED7C4CE-46EC-42D0-B81B-F6C31D8CBD1F \
/tmp/aim-derived-data/Build/Products/Debug-iphonesimulator/AimApp.app

DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer \
xcrun simctl launch 7ED7C4CE-46EC-42D0-B81B-F6C31D8CBD1F com.aim.pregnancy
```

**Step 4: Perform manual acceptance**

In Simulator:

1. enter the demo account;
2. open “记录”;
3. create a symptom record with severity and family visibility;
4. confirm it appears in the timeline;
5. create a checkup record and a note;
6. open the symptom record and turn it into a task;
7. open “计划” and confirm the new task has source `record` through the API response;
8. open Agent and ask it to summarize recent records;
9. verify no private record appears when using another family account.

**Step 5: Final verification**

Run `git diff --check`, confirm `git status --short` is clean except for intentionally uncommitted user work, and record API/iOS/Agent test counts in the handoff.
