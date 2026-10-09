"""Let an account request its own deletion and remember when."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0008_account_deletion"
down_revision = "0007_agent_sessions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # status 本来就是 String(20)，新值 pending_deletion 直接写入即可，不需要改列。
    op.add_column(
        "accounts",
        sa.Column("deletion_requested_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("accounts", "deletion_requested_at")
