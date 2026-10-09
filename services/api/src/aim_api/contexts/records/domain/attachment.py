from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from aim_api.contexts.records.domain.errors import AttachmentRejected, AttachmentUnavailable

#: 网页端会把图片压成 JPEG 再传；另两种留给以后的入口。
ALLOWED_MEDIA_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_ATTACHMENT_BYTES = 2 * 1024 * 1024
MAX_ATTACHMENTS_PER_RECORD = 4


@dataclass(slots=True)
class Attachment:
    id: UUID
    family_id: UUID
    pregnancy_id: UUID
    uploaded_by: UUID | None
    media_type: str
    byte_size: int
    record_id: UUID | None
    created_at: datetime

    @classmethod
    def upload(
        cls,
        *,
        attachment_id: UUID,
        family_id: UUID,
        pregnancy_id: UUID,
        uploaded_by: UUID,
        media_type: str,
        byte_size: int,
        now: datetime | None = None,
    ) -> Attachment:
        if media_type not in ALLOWED_MEDIA_TYPES:
            raise AttachmentRejected("bad_type", "只支持 JPEG、PNG、WebP 图片")
        if byte_size <= 0 or byte_size > MAX_ATTACHMENT_BYTES:
            raise AttachmentRejected("too_large", "图片不能超过 2 MB")
        return cls(
            id=attachment_id,
            family_id=family_id,
            pregnancy_id=pregnancy_id,
            uploaded_by=uploaded_by,
            media_type=media_type,
            byte_size=byte_size,
            record_id=None,
            created_at=now or datetime.now(UTC),
        )

    def attach_to(self, record_id: UUID) -> None:
        if self.record_id is not None:
            raise AttachmentUnavailable("这张图片已经挂在别的记录上了")
        self.record_id = record_id
