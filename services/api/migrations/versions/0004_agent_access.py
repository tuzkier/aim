"""Create Agent Access tool invocation table."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0004_agent_access"
down_revision = "0003_planning"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "tool_invocations",
        sa.Column("operation_id", uuid, primary_key=True),
        sa.Column("session_id", sa.String(length=160), nullable=False),
        sa.Column("call_id", sa.String(length=160), nullable=False),
        sa.Column("tool_name", sa.String(length=120), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("result_json", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_tool_invocations_session_call",
        "tool_invocations",
        ["session_id", "call_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_tool_invocations_session_call", table_name="tool_invocations")
    op.drop_table("tool_invocations")
