"""Record AIM conversation sessions so they can be listed and reopened."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0007_agent_sessions"
down_revision = "0006_password_and_nickname"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "agent_sessions",
        sa.Column("id", uuid, primary_key=True),
        # 按账号隔离，不是按家庭：孕期会问很私人的事，
        # 默认全家可见会让人不敢问。
        sa.Column(
            "account_id",
            uuid,
            sa.ForeignKey("accounts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # 只为按家庭清理数据方便，不参与鉴权。
        sa.Column(
            "family_id",
            uuid,
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # Eve 那边的 wrun_*。对话内容留在 Eve，这里只存引用。
        sa.Column("eve_session_id", sa.Text(), nullable=False),
        sa.Column("title", sa.String(length=80), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
    )
    # 列表查询只按账号过滤、按活跃时间排序。
    op.create_index(
        "ix_agent_sessions_account_active",
        "agent_sessions",
        ["account_id", "last_active_at"],
    )
    # 同一个 Eve 会话不该被登记两次。
    op.create_unique_constraint(
        "uq_agent_sessions_eve_id", "agent_sessions", ["eve_session_id"]
    )


def downgrade() -> None:
    op.drop_constraint("uq_agent_sessions_eve_id", "agent_sessions", type_="unique")
    op.drop_index("ix_agent_sessions_account_active", table_name="agent_sessions")
    op.drop_table("agent_sessions")
