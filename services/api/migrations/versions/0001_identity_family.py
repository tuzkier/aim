"""Create Identity and Family persistence tables."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0001_identity_family"
down_revision = "0000_baseline"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid = sa.Uuid(as_uuid=True)
    op.create_table(
        "accounts",
        sa.Column("id", uuid, primary_key=True),
        sa.Column("phone", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("phone", name="uq_accounts_phone"),
    )
    op.create_table(
        "families",
        sa.Column("id", uuid, primary_key=True),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column(
            "created_by",
            uuid,
            sa.ForeignKey("accounts.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "family_members",
        sa.Column(
            "family_id",
            uuid,
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "account_id",
            uuid,
            sa.ForeignKey("accounts.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("role", sa.String(length=30), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("invited_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_table(
        "family_invitations",
        sa.Column("id", uuid, primary_key=True),
        sa.Column(
            "family_id",
            uuid,
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "invited_by",
            uuid,
            sa.ForeignKey("accounts.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("invitee_phone", sa.String(length=20), nullable=False),
        sa.Column("role", sa.String(length=30), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "accepted_account_id",
            uuid,
            sa.ForeignKey("accounts.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_family_invitations_token_hash",
        "family_invitations",
        ["token_hash"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_family_invitations_token_hash", table_name="family_invitations")
    op.drop_table("family_invitations")
    op.drop_table("family_members")
    op.drop_table("families")
    op.drop_table("accounts")
