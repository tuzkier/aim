from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.family.adapters.outbound.persistence.models import (
    AccountModel,
    FamilyInvitationModel,
    FamilyMemberModel,
    FamilyModel,
)
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.family.domain.family import (
    Family,
    FamilyMember,
    FamilyMemberRole,
    FamilyMemberStatus,
)
from aim_api.contexts.family.domain.errors import FamilyMemberNotFound, FamilyNotFound
from aim_api.contexts.family.domain.invitation import Invitation, InvitationStatus
from aim_api.contexts.identity.domain.account import Account, AccountStatus


class SqlAlchemyFamilyRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def ensure_account(self, account: Account) -> Account:
        model = await self.session.get(AccountModel, account.id)
        if model is None:
            model = AccountModel(
                id=account.id,
                phone=account.phone,
                status=account.status.value,
                password_hash=account.password_hash,
                created_at=account.created_at,
            )
            self.session.add(model)
            await self.session.flush()
            return account
        if model.phone != account.phone:
            raise ValueError("account phone does not match session identity")
        return _to_account(model)

    async def get_account(self, account_id: UUID) -> Account | None:
        model = await self.session.get(AccountModel, account_id)
        return _to_account(model) if model else None

    async def get_account_by_phone(self, phone: str) -> Account | None:
        model = await self.session.scalar(select(AccountModel).where(AccountModel.phone == phone))
        return _to_account(model) if model else None

    async def get_first_family_for_account(self, account_id: UUID) -> Family | None:
        family_id = await self.session.scalar(
            select(FamilyMemberModel.family_id)
            .where(
                FamilyMemberModel.account_id == account_id,
                FamilyMemberModel.status == FamilyMemberStatus.active.value,
            )
            .order_by(FamilyMemberModel.joined_at, FamilyMemberModel.family_id)
            .limit(1)
        )
        return await self.get_family(family_id) if family_id else None

    async def is_active_member(self, family_id: UUID, account_id: UUID) -> bool:
        member = await self.session.scalar(
            select(FamilyMemberModel).where(
                FamilyMemberModel.family_id == family_id,
                FamilyMemberModel.account_id == account_id,
                FamilyMemberModel.status == FamilyMemberStatus.active.value,
            )
        )
        return member is not None

    async def add_family(self, family: Family) -> None:
        self.session.add(
            FamilyModel(
                id=family.id,
                name=family.name,
                created_by=family.created_by,
                created_at=family.created_at,
            )
        )
        await self.session.flush()

    async def get_family(self, family_id: UUID) -> Family | None:
        model = await self.session.get(FamilyModel, family_id)
        if model is None:
            return None
        member_models = (
            await self.session.scalars(
                select(FamilyMemberModel).where(FamilyMemberModel.family_id == family_id)
            )
        ).all()
        family = Family.create(model.id, model.name, model.created_by, model.created_at)
        for member_model in member_models:
            family.add_member(_to_member(member_model))
        return family

    async def add_member(self, family_id: UUID, member: FamilyMember) -> None:
        self.session.add(
            FamilyMemberModel(
                family_id=family_id,
                account_id=member.account_id,
                role=member.role.value,
                status=member.status.value,
                nickname=member.nickname,
                invited_at=member.invited_at,
                joined_at=member.joined_at,
            )
        )

    async def activate_member(self, family_id: UUID, account_id: UUID, joined_at: datetime) -> None:
        await self.session.execute(
            update(FamilyMemberModel)
            .where(
                FamilyMemberModel.family_id == family_id,
                FamilyMemberModel.account_id == account_id,
            )
            .values(status=FamilyMemberStatus.active.value, joined_at=joined_at)
        )

    async def rename_family(self, family_id: UUID, name: str) -> None:
        model = await self.session.get(FamilyModel, family_id)
        if model is None:
            raise FamilyNotFound(str(family_id))
        model.name = name

    async def update_member_profile(
        self,
        family_id: UUID,
        account_id: UUID,
        *,
        nickname: str | None,
        role: FamilyMemberRole | None,
    ) -> None:
        """改成员的称呼和角色。只被 /members/me 调用——改别人需要一套权限模型。"""
        model = await self.session.get(FamilyMemberModel, (family_id, account_id))
        if model is None:
            raise FamilyMemberNotFound(str(account_id))
        # None 表示这次不改这一项，而不是「清空」。两者必须区分开，
        # 否则只想改称呼的请求会把角色抹掉。
        if nickname is not None:
            model.nickname = nickname
        if role is not None:
            model.role = role.value

    async def get_invitation_by_hash(self, token_hash: str) -> Invitation | None:
        model = await self.session.scalar(
            select(FamilyInvitationModel).where(FamilyInvitationModel.token_hash == token_hash)
        )
        return _to_invitation(model) if model else None

    async def add_invitation(self, invitation: Invitation) -> None:
        self.session.add(_to_invitation_model(invitation))

    async def save_invitation(self, invitation: Invitation) -> None:
        await self.session.execute(
            update(FamilyInvitationModel)
            .where(FamilyInvitationModel.id == invitation.id)
            .values(
                status=invitation.status.value,
                accepted_account_id=invitation.accepted_account_id,
                accepted_at=invitation.accepted_at,
            )
        )


class SqlAlchemyFamilyUnitOfWork:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = SqlAlchemyFamilyRepository(session)
        self._session = session

    async def commit(self) -> None:
        try:
            await self._session.commit()
        except IntegrityError as error:
            await self._session.rollback()
            raise PersistenceConflict("family persistence constraint failed") from error

    async def rollback(self) -> None:
        await self._session.rollback()


def _to_account(model: AccountModel) -> Account:
    return Account(
        id=model.id,
        phone=model.phone,
        password_hash=model.password_hash,
        status=AccountStatus(model.status),
        created_at=model.created_at,
    )


def _to_member(model: FamilyMemberModel) -> FamilyMember:
    return FamilyMember(
        account_id=model.account_id,
        role=FamilyMemberRole(model.role),
        status=FamilyMemberStatus(model.status),
        nickname=model.nickname,
        invited_at=model.invited_at,
        joined_at=model.joined_at,
    )


def _to_invitation(model: FamilyInvitationModel) -> Invitation:
    return Invitation(
        id=model.id,
        family_id=model.family_id,
        invited_by=model.invited_by,
        invitee_phone=model.invitee_phone,
        role=FamilyMemberRole(model.role),
        token_hash=model.token_hash,
        created_at=model.created_at,
        expires_at=model.expires_at,
        status=InvitationStatus(model.status),
        accepted_account_id=model.accepted_account_id,
        accepted_at=model.accepted_at,
    )


def _to_invitation_model(invitation: Invitation) -> FamilyInvitationModel:
    return FamilyInvitationModel(
        id=invitation.id,
        family_id=invitation.family_id,
        invited_by=invitation.invited_by,
        invitee_phone=invitation.invitee_phone,
        role=invitation.role.value,
        token_hash=invitation.token_hash,
        status=invitation.status.value,
        created_at=invitation.created_at,
        expires_at=invitation.expires_at,
        accepted_account_id=invitation.accepted_account_id,
        accepted_at=invitation.accepted_at,
    )
