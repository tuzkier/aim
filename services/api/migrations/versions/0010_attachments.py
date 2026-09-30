"""Store uploaded images and link them to records."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0010_attachments"
down_revision = "0009_tool_invocation_scope"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "attachments",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("pregnancy_id", sa.Uuid(), nullable=False),
        sa.Column("uploaded_by", sa.Uuid(), nullable=True),
        sa.Column("media_type", sa.String(40), nullable=False),
        sa.Column("byte_size", sa.Integer(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_attachments_record", "attachments", ["record_id"])
    op.create_index("ix_attachments_family", "attachments", ["family_id"])


def downgrade() -> None:
    op.drop_index("ix_attachments_family", table_name="attachments")
    op.drop_index("ix_attachments_record", table_name="attachments")
    op.drop_table("attachments")
