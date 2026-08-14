"""Establish the initial migration stream."""

from __future__ import annotations

from alembic import op

revision = "0000_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
