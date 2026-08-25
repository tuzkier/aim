"""Add password hash to accounts and nickname to family members."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from aim_api.migrations_support import UNUSABLE_PASSWORD_MARKER as UNUSABLE_PASSWORD

revision = "0006_password_and_nickname"
down_revision = "0005_records"
branch_labels = None
depends_on = None

def upgrade() -> None:
    # 三步走而不是直接 ADD COLUMN NOT NULL：后者在有存量行的库上必然失败。
    # 别把「库是空的」当成迁移的前提——生产恰好是空的，开发库不是。
    op.add_column("accounts", sa.Column("password_hash", sa.Text(), nullable=True))
    op.execute(
        sa.text("UPDATE accounts SET password_hash = :value WHERE password_hash IS NULL").bindparams(
            value=UNUSABLE_PASSWORD
        )
    )
    op.alter_column("accounts", "password_hash", nullable=False)

    # 称呼可空：邀请中还没填的成员就是没有，渲染时回退到角色名。
    op.add_column("family_members", sa.Column("nickname", sa.String(length=60), nullable=True))


def downgrade() -> None:
    op.drop_column("family_members", "nickname")
    op.drop_column("accounts", "password_hash")
