from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyUnitOfWork,
)
from aim_api.contexts.family.application.commands import create_family
from aim_api.contexts.family.application.commands.create_family import CreateFamilyCommand
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.guidance.application.queries.get_guidance import initial_plan_items
from aim_api.contexts.identity.domain.account import AccountStatus
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.application.commands import generate_initial_plan
from aim_api.contexts.planning.application.commands.generate_initial_plan import (
    GenerateInitialPlanCommand,
    TaskSeed,
)
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyUnitOfWork,
)
from aim_api.contexts.pregnancy.application.commands import create_pregnancy
from aim_api.contexts.pregnancy.application.commands.create_pregnancy import (
    CreatePregnancyCommand,
)
from aim_api.platform.auth.context import authenticate, issue_session_token
from aim_api.platform.auth.passwords import (
    MIN_PASSWORD_LENGTH,
    hash_password,
    verify_password,
)
from aim_api.platform.config.settings import Settings
from aim_api.platform.database.session import Database

router = APIRouter(tags=["identity"])


class LoginRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    # 登录不校验密码长度：规则变严时老密码仍要能登进来，
    # 而且在这里校验等于告诉攻击者「这个长度不可能是真密码」。
    password: str = Field(min_length=1, max_length=200)


class RegisterRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    # 长度是密码强度里真正起作用的维度，所以只管长度，不要求字符组合。
    password: str = Field(min_length=MIN_PASSWORD_LENGTH, max_length=200)
    role: FamilyMemberRole
    nickname: str | None = Field(default=None, max_length=60)
    due_date: date | None = None


class SessionResponse(BaseModel):
    account_id: UUID
    phone: str
    family_id: UUID
    pregnancy_id: UUID | None
    role: FamilyMemberRole
    token: str
    #: 登录时顺手撤销了注销申请。客户端据此提示「欢迎回来」。
    deletion_cancelled: bool = False


async def _ensure_family_and_pregnancy(
    payload: RegisterRequest | LoginRequest,
    account_id: UUID,
    database: Database,
    *,
    password_hash: str = "",
    role: FamilyMemberRole = FamilyMemberRole.mother,
    nickname: str | None = None,
) -> tuple[UUID, UUID | None, bool]:
    created = False
    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        family = await family_uow.repository.get_first_family_for_account(account_id)
        if family is None:
            family = await create_family.execute(
                CreateFamilyCommand(
                    account_id=account_id,
                    phone=payload.phone,
                    name="我的家庭",
                    role=role,
                    password_hash=password_hash,
                    nickname=nickname,
                ),
                family_uow,
            )
            created = True

        pregnancy = None
        if payload.due_date is not None:
            pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
            pregnancy = await pregnancy_uow.repository.get_first_pregnancy_for_family(family.id)
            if pregnancy is None:
                pregnancy = await create_pregnancy.execute(
                    CreatePregnancyCommand(
                        family_id=family.id,
                        account_id=account_id,
                        due_date=payload.due_date,
                    ),
                    pregnancy_uow,
                )
                created = True
        else:
            pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
            pregnancy = await pregnancy_uow.repository.get_first_pregnancy_for_family(family.id)

        return family.id, pregnancy.id if pregnancy is not None else None, created


async def _ensure_initial_plan(
    pregnancy_id: UUID,
    account_id: UUID,
    database: Database,
) -> None:
    as_of = date.today()
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
        if pregnancy is None:
            return
        age = pregnancy.gestational_age(as_of)
        seeds = _initial_task_seeds(age.weeks, as_of)
        existing_plan = await uow.repository.get_plan(pregnancy_id)
        if existing_plan is not None:
            if existing_plan.tasks or not seeds:
                return
            for seed in seeds:
                task = Task.create(
                    task_id=uuid4(),
                    plan_id=existing_plan.id,
                    pregnancy_id=pregnancy_id,
                    title=seed.title,
                    description=seed.description,
                    source_type=seed.source_type,
                    source_id=seed.source_id,
                    changed_by_actor_type=seed.changed_by_actor_type,
                    changed_by_actor_id=seed.changed_by_actor_id,
                    due_at=seed.due_at,
                    assigned_member_id=seed.assigned_member_id,
                    now=datetime.combine(as_of, time(0), tzinfo=UTC),
                )
                existing_plan.add_task(task)
                await uow.repository.add_task(task)
            await uow.commit()
            return
        await generate_initial_plan.execute(
            GenerateInitialPlanCommand(
                pregnancy_id=pregnancy_id,
                family_id=pregnancy.family_id,
                account_id=account_id,
                tasks=seeds,
                now=datetime.combine(as_of, time(0), tzinfo=UTC),
            ),
            uow,
        )


def _initial_task_seeds(gestational_week: int, as_of: date) -> tuple[TaskSeed, ...]:
    return tuple(
        TaskSeed(
            title=item.title,
            description=item.summary,
            source_type=TaskSourceType.template,
            source_id=item.id,
            changed_by_actor_type=ActorType.system,
            changed_by_actor_id=None,
            due_at=datetime.combine(
                as_of + timedelta(days=item.due_in_days),
                time(9, 0),
                tzinfo=UTC,
            ),
        )
        for item in initial_plan_items(gestational_week)
    )


@router.post("/api/v1/auth/register", response_model=SessionResponse, status_code=201)
async def register(payload: RegisterRequest, request: Request) -> SessionResponse:
    settings: Settings = request.app.state.settings
    database: Database = request.app.state.database

    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        existing = await family_uow.repository.get_account_by_phone(payload.phone)
    if existing is not None:
        # 注册接口区分「已注册」是必要的——用户得知道该去登录。登录接口则相反，
        # 那里区分开就成了手机号枚举器。
        raise HTTPException(status_code=409, detail="该手机号已经注册过了")

    account_id = uuid4()
    family_id, pregnancy_id, _ = await _ensure_family_and_pregnancy(
        payload,
        account_id,
        database,
        password_hash=hash_password(payload.password),
        role=payload.role,
        nickname=payload.nickname,
    )
    if pregnancy_id is not None:
        await _ensure_initial_plan(pregnancy_id, account_id, database)

    return SessionResponse(
        account_id=account_id,
        phone=payload.phone,
        family_id=family_id,
        pregnancy_id=pregnancy_id,
        role=payload.role,
        token=issue_session_token(account_id, payload.phone, settings.auth_secret),
    )


#: 手机号不存在时也要走一次真实的哈希校验。直接返回会让「不存在」比「密码错」
#: 快一个数量级，响应时间就把答案说出来了。这个哈希对应一个不可能被猜中的密码。
_DUMMY_HASH = hash_password("no-account-with-this-phone-exists")

LOGIN_FAILURE = "手机号或密码不对"


@router.post("/api/v1/auth/login", response_model=SessionResponse, status_code=200)
async def login(payload: LoginRequest, request: Request) -> SessionResponse:
    settings: Settings = request.app.state.settings
    database: Database = request.app.state.database

    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        account = await family_uow.repository.get_account_by_phone(payload.phone)

        hashed = account.password_hash if account is not None else _DUMMY_HASH
        password_ok = verify_password(payload.password, hashed)
        if account is None or not password_ok:
            # 「账号不存在」和「密码错误」返回完全一样的东西。区分开，
            # 这个接口就成了手机号枚举器。
            raise HTTPException(status_code=401, detail=LOGIN_FAILURE)

        now = datetime.now(UTC)
        if not account.can_log_in(now=now):
            # 已停用 / 缓冲期已过：对外和「账号不存在」一模一样。
            raise HTTPException(status_code=401, detail=LOGIN_FAILURE)
        deletion_cancelled = account.status is AccountStatus.pending_deletion
        if deletion_cancelled:
            account.cancel_deletion()
            await family_uow.repository.save_account_status(account)
            await family_uow.commit()

        # 登录不建任何东西：账号既然注册过，家庭就已经存在。
        family = await family_uow.repository.get_first_family_for_account(account.id)
        if family is None:
            raise HTTPException(status_code=409, detail="账号没有关联的家庭，请联系管理员")
        member = family.members.get(account.id)

        pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
        pregnancy = await pregnancy_uow.repository.get_first_pregnancy_for_family(family.id)

    return SessionResponse(
        account_id=account.id,
        phone=account.phone,
        family_id=family.id,
        pregnancy_id=pregnancy.id if pregnancy is not None else None,
        role=member.role if member is not None else FamilyMemberRole.mother,
        token=issue_session_token(account.id, account.phone, settings.auth_secret),
        deletion_cancelled=deletion_cancelled,
    )


class DeletionRequest(BaseModel):
    password: str = Field(min_length=1, max_length=200)


@router.post("/api/v1/auth/deletion-request", status_code=204)
async def request_deletion(payload: DeletionRequest, request: Request) -> Response:
    """申请注销。30 天内重新登录即撤销，到期由 scripts/purge_deleted_accounts.py 删除。

    只验签、不检查状态：已在缓冲期的账号再点一次应当幂等成功，而不是 401。
    """
    actor = authenticate(request)
    database: Database = request.app.state.database

    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        account = await family_uow.repository.get_account(actor.account_id)
        hashed = account.password_hash if account is not None else _DUMMY_HASH
        # 先算哈希再看状态：停用账号也得花同样的时间，不然响应时间就把状态说出来了。
        password_ok = verify_password(payload.password, hashed)
        # 停用账号按「密码错」处理：否则它申请注销、再在 30 天内登录，
        # 就会经由「撤销注销」把自己变回 active。
        if account is None or account.status is AccountStatus.disabled or not password_ok:
            raise HTTPException(status_code=401, detail=LOGIN_FAILURE)
        account.request_deletion(now=datetime.now(UTC))
        await family_uow.repository.save_account_status(account)
        await family_uow.commit()
    return Response(status_code=204)
