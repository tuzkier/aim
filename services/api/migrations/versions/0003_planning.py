"""Create pregnancy plan, task and task change tables."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0003_planning"
down_revision = "0002_pregnancy"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "pregnancy_plans",
        sa.Column("id", uuid, primary_key=True),
        sa.Column("pregnancy_id", uuid, nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("pregnancy_id", name="uq_pregnancy_plans_pregnancy_id"),
    )
    op.create_table(
        "tasks",
        sa.Column("id", uuid, primary_key=True),
        sa.Column(
            "plan_id",
            uuid,
            sa.ForeignKey("pregnancy_plans.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("pregnancy_id", uuid, nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.String(length=2000), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("source_type", sa.String(length=30), nullable=False),
        sa.Column("source_id", sa.String(length=160), nullable=True),
        sa.Column("changed_by_actor_type", sa.String(length=20), nullable=False),
        sa.Column("changed_by_actor_id", uuid, nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("scheduled_for", sa.DateTime(timezone=True), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("assigned_member_id", uuid, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_tasks_plan_due_at", "tasks", ["plan_id", "due_at"])
    op.create_table(
        "task_changes",
        sa.Column("id", uuid, primary_key=True),
        sa.Column(
            "task_id",
            uuid,
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("operation", sa.String(length=30), nullable=False),
        sa.Column("before_json", sa.JSON(), nullable=False),
        sa.Column("after_json", sa.JSON(), nullable=False),
        sa.Column("version_before", sa.Integer(), nullable=False),
        sa.Column("version_after", sa.Integer(), nullable=False),
        sa.Column("changed_by_actor_type", sa.String(length=20), nullable=False),
        sa.Column("changed_by_actor_id", uuid, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("task_changes")
    op.drop_index("ix_tasks_plan_due_at", table_name="tasks")
    op.drop_table("tasks")
    op.drop_table("pregnancy_plans")
