from datetime import UTC, datetime
import json
from pathlib import Path
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError
from aim_api.contexts.records.domain.mental_health import EPDS_VERSION, epds_result
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

LOW = [0, 0, 3, 0, 3, 3, 3, 3, 3, 3]
HIGH = [3, 3, 0, 3, 0, 0, 0, 0, 0, 0]


def make(kind, data, *, content=None, visibility=RecordVisibility.private):
    return Record.create(record_id=uuid4(), pregnancy_id=uuid4(), family_id=uuid4(),
                         author_account_id=uuid4(), record_type=kind,
                         occurred_at=datetime.now(UTC), visibility=visibility,
                         structured_data=data, content=content)


def test_original_answer_order_and_extremes():
    assert epds_result(LOW) == {"score": 0, "item_10": 0, "support_level": "support"}
    assert epds_result(HIGH) == {"score": 30, "item_10": 3, "support_level": "immediate"}
    assert epds_result([1] * 10)["score"] == 17


@pytest.mark.parametrize("total,level", [(9, "support"), (10, "follow_up"), (12, "follow_up"), (13, "assessment")])
def test_score_thresholds(total, level):
    answers = LOW.copy()
    left = total
    for i in range(9):
        points = min(3, left)
        answers[i] = points if i in (0, 1, 3) else 3 - points
        left -= points
    assert epds_result(answers)["support_level"] == level


def test_item_ten_overrides_a_low_total():
    answers = LOW.copy(); answers[9] = 2
    assert epds_result(answers) == {"score": 1, "item_10": 1, "support_level": "immediate"}


@pytest.mark.parametrize("answers", [[], LOW[:9], LOW + [0], [False] + LOW[1:], [4] + LOW[1:], [-1] + LOW[1:], [0.0] + LOW[1:], "1234567890"])
def test_incomplete_or_invalid_answers_are_rejected(answers):
    with pytest.raises(RecordValidationError): epds_result(answers)


def test_epds_server_overrides_client_scores():
    r = make(RecordType.epds, {"version": EPDS_VERSION, "answers": LOW, "score": 30, "item_10": 3, "support_level": "immediate"})
    assert r.structured_data == {"version": EPDS_VERSION, "answers": LOW, "period": "manual", **epds_result(LOW)}
    with pytest.raises(RecordValidationError):
        make(RecordType.epds, {"version": "unknown", "answers": LOW})
    with pytest.raises(RecordValidationError):
        make(RecordType.epds, {"version": EPDS_VERSION, "answers": LOW, "period": "made-up"})


def test_bundle_questionnaire_is_the_same_scoring_version():
    path = Path(__file__).resolve().parents[5] / "content/mental-health/epds-zh-Hans.json"
    data = json.loads(path.read_text())
    assert data["version"] == EPDS_VERSION
    assert len(data["questions"]) == 10
    for i, question in enumerate(data["questions"]):
        assert question["points"] == ([0, 1, 2, 3] if i in (0, 1, 3) else [3, 2, 1, 0])
        assert len(question["options"]) == 4


@pytest.mark.parametrize("data", [{"mood": True}, {"mood": 0}, {"mood": 6}, {"mood": 2, "tags": ["bad"]}, {"mood": 2, "tags": ["sleep", "sleep"]}, {"mood": 2, "tags": "sleep"}, {"mood": 2, "extra": 1}])
def test_mood_validation(data):
    with pytest.raises(RecordValidationError): make(RecordType.mood, data)


def test_mood_defaults_and_note_limit():
    assert make(RecordType.mood, {"mood": 2}).structured_data == {"mood": 2, "tags": []}
    make(RecordType.mood, {"mood": 5, "tags": ["sleep", "support"]}, content="好" * 500)
    with pytest.raises(RecordValidationError): make(RecordType.mood, {"mood": 2}, content="好" * 501)


@pytest.mark.parametrize("kind,data", [(RecordType.mood, {"mood": 2}), (RecordType.epds, {"version": EPDS_VERSION, "answers": LOW})])
def test_shared_emotional_records_remain_author_only_for_mutation(kind, data):
    r = make(kind, data, visibility=RecordVisibility.family)
    r.assert_can_mutate(r.author_account_id)
    with pytest.raises(RecordAccessDenied): r.assert_can_mutate(uuid4())
