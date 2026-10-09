"""Record whom an agent tool call acted for, and whether it has been undone."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0009_tool_invocation_scope"
down_revision = "0008_account_deletion"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 历史行这几列为空：它们没法经公开接口撤销，这是可以接受的——
    # 撤销针对的是刚刚发生的事，不是几周前的调用。
    op.add_column("tool_invocations", sa.Column("account_id", sa.Uuid(), nullable=True))
    op.add_column("tool_invocations", sa.Column("family_id", sa.Uuid(), nullable=True))
    op.add_column("tool_invocations", sa.Column("pregnancy_id", sa.Uuid(), nullable=True))
    op.add_column(
        "tool_invocations",
        sa.Column("undone_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_tool_invocations_account", "tool_invocations", ["account_id"])


def downgrade() -> None:
    op.drop_index("ix_tool_invocations_account", table_name="tool_invocations")
    op.drop_column("tool_invocations", "undone_at")
    op.drop_column("tool_invocations", "pregnancy_id")
    op.drop_column("tool_invocations", "family_id")
    op.drop_column("tool_invocations", "account_id")
