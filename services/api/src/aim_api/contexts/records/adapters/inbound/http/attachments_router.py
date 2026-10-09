"""图片附件的上传与查看。

上传收图片原始字节（不用表单），网页端已经压缩过；查看只对附件所属家庭的在籍成员开放，
其他人一律 404——既不暴露内容，也不暴露「这个编号存在」。
"""

from __future__ import annotations

from uuid import UUID, uuid4

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel

from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage
from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENT_BYTES, Attachment
from aim_api.contexts.records.domain.errors import AttachmentRejected
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ApiError, ForbiddenError, NotFoundError

router = APIRouter(tags=["attachments"])


class PayloadTooLarge(ApiError):
    status_code = 413
    code = "attachment.too_large"


class UnsupportedMediaType(ApiError):
    status_code = 415
    code = "attachment.bad_type"


class AttachmentResponse(BaseModel):
    id: UUID
    media_type: str
    byte_size: int


def attachment_storage(request: Request) -> LocalAttachmentStorage:
    return LocalAttachmentStorage(request.app.state.settings.attachments_root)


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/attachments",
    response_model=AttachmentResponse,
    status_code=201,
)
async def upload_attachment(pregnancy_id: UUID, request: Request) -> AttachmentResponse:
    actor = await authenticate_active(request)
    declared = int(request.headers.get("content-length") or 0)
    if declared > MAX_ATTACHMENT_BYTES:
        raise PayloadTooLarge("图片不能超过 2 MB")
    data = await request.body()
    media_type = (request.headers.get("content-type") or "").split(";")[0].strip()

    async with request.app.state.database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
        if pregnancy is None or not await uow.family_membership.is_active_member(
            pregnancy.family_id, actor.account_id
        ):
            raise ForbiddenError("不能往这段孕期上传图片")
        try:
            attachment = Attachment.upload(
                attachment_id=uuid4(),
                family_id=pregnancy.family_id,
                pregnancy_id=pregnancy_id,
                uploaded_by=actor.account_id,
                media_type=media_type,
                byte_size=len(data),
            )
        except AttachmentRejected as error:
            if error.kind == "too_large":
                raise PayloadTooLarge(str(error)) from error
            raise UnsupportedMediaType(str(error)) from error

        storage = attachment_storage(request)
        storage.save(attachment.id, data)
        try:
            await uow.attachments.add(attachment)
            await uow.commit()
        except Exception:
            # 行没写进去，文件就不该留着。
            storage.delete(attachment.id)
            raise
    return AttachmentResponse(
        id=attachment.id, media_type=attachment.media_type, byte_size=attachment.byte_size
    )


@router.get("/api/v1/attachments/{attachment_id}")
async def read_attachment(attachment_id: UUID, request: Request) -> Response:
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        attachment = await uow.attachments.get(attachment_id)
        if attachment is None or not await uow.family_membership.is_active_member(
            attachment.family_id, actor.account_id
        ):
            raise NotFoundError("没有找到这张图片")
    data = attachment_storage(request).read(attachment_id)
    if data is None:
        raise NotFoundError("没有找到这张图片")
    # 编号对应的内容永不改变，可以长期缓存；private 保证只缓存在本人设备上。
    return Response(
        content=data,
        media_type=attachment.media_type,
        headers={"Cache-Control": "private, max-age=31536000, immutable"},
    )
