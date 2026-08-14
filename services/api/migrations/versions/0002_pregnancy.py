"""Create Pregnancy Journey persistence tables."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0002_pregnancy"
down_revision = "0001_identity_family"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "pregnancies",
        sa.Column("id", uuid, primary_key=True),
        sa.Column("family_id", uuid, nullable=False),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("created_by", uuid, nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "pregnancy_facts",
        sa.Column("id", uuid, primary_key=True),
        sa.Column(
            "pregnancy_id",
            uuid,
            sa.ForeignKey("pregnancies.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("fact_key", sa.String(length=120), nullable=False),
        sa.Column("value_json", sa.JSON(), nullable=False),
        sa.Column("source", sa.String(length=30), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_by_account_id", uuid, nullable=False),
        sa.Column("supersedes_fact_id", uuid, nullable=True),
    )
    op.create_index(
        "ix_pregnancy_facts_pregnancy_key",
        "pregnancy_facts",
        ["pregnancy_id", "fact_key"],
    )


def downgrade() -> None:
    op.drop_index("ix_pregnancy_facts_pregnancy_key", table_name="pregnancy_facts")
    op.drop_table("pregnancy_facts")
    op.drop_table("pregnancies")
