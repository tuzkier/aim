from __future__ import annotations

from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENT_BYTES, Attachment
from aim_api.contexts.records.domain.errors import AttachmentRejected, AttachmentUnavailable


def _upload(**overrides):
    values = dict(
        attachment_id=uuid4(),
        family_id=uuid4(),
        pregnancy_id=uuid4(),
        uploaded_by=uuid4(),
        media_type="image/jpeg",
        byte_size=1000,
    )
    values.update(overrides)
    return Attachment.upload(**values)


def test_accepts_a_small_jpeg() -> None:
    attachment = _upload()
    assert attachment.record_id is None


def test_rejects_other_types() -> None:
    with pytest.raises(AttachmentRejected) as caught:
        _upload(media_type="application/pdf")
    assert caught.value.kind == "bad_type"


def test_rejects_anything_over_two_megabytes() -> None:
    with pytest.raises(AttachmentRejected) as caught:
        _upload(byte_size=MAX_ATTACHMENT_BYTES + 1)
    assert caught.value.kind == "too_large"


def test_can_only_be_attached_once() -> None:
    attachment = _upload()
    attachment.attach_to(uuid4())
    with pytest.raises(AttachmentUnavailable):
        attachment.attach_to(uuid4())
