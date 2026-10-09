"""Family activity events, task creators, and invitations without pending members."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0011_family_events"
down_revision = "0010_attachments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "family_events",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(40), nullable=False),
        sa.Column("actor_account_id", sa.Uuid(), nullable=True),
        sa.Column("subject_account_id", sa.Uuid(), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_family_events_family_created", "family_events", ["family_id", "created_at"])

    op.add_column("tasks", sa.Column("created_by_actor_type", sa.String(20), nullable=True))
    op.add_column("tasks", sa.Column("created_by_actor_id", sa.Uuid(), nullable=True))
    # 旧数据不知道最初是谁建的，用最近一次改动人近似。
    op.execute(
        "UPDATE tasks SET created_by_actor_type = changed_by_actor_type, "
        "created_by_actor_id = changed_by_actor_id"
    )
    op.alter_column("tasks", "created_by_actor_type", nullable=False)

    # 邀请不再预先插入「待确认」成员：待处理的邀请直接列在家庭里。
    op.execute("DELETE FROM family_members WHERE status = 'pending'")


def downgrade() -> None:
    op.drop_column("tasks", "created_by_actor_id")
    op.drop_column("tasks", "created_by_actor_type")
    op.drop_index("ix_family_events_family_created", table_name="family_events")
    op.drop_table("family_events")
