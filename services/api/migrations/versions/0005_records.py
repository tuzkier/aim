"""Create pregnancy records table."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0005_records"
down_revision = "0004_agent_access"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "records",
        sa.Column("id", uuid, primary_key=True),
        sa.Column("pregnancy_id", uuid, nullable=False),
        sa.Column("family_id", uuid, nullable=False),
        sa.Column("author_account_id", uuid, nullable=False),
        sa.Column("record_type", sa.String(length=20), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("visibility", sa.String(length=20), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=True),
        sa.Column("content", sa.String(length=5000), nullable=True),
        sa.Column("structured_data", sa.JSON(), nullable=False),
        sa.Column("attachment_refs", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_records_pregnancy_occurred_at", "records", ["pregnancy_id", "occurred_at"]
    )
    op.create_index("ix_records_family_visibility", "records", ["family_id", "visibility"])


def downgrade() -> None:
    op.drop_index("ix_records_family_visibility", table_name="records")
    op.drop_index("ix_records_pregnancy_occurred_at", table_name="records")
    op.drop_table("records")
