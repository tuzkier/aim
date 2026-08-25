"""Add password hash to accounts and nickname to family members."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0006_password_and_nickname"
down_revision = "0005_records"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # NOT NULL 且不给 server_default：库当前为空，没有存量行需要回填，
    # 而一个默认值会让「没有密码的账号」这种非法状态变得可表达。
    op.add_column("accounts", sa.Column("password_hash", sa.Text(), nullable=False))
    # 称呼可空：只有角色的成员在列表里长得一模一样，两个「其他家人」分不出谁是谁。
    # 允许为空是因为老成员和邀请中的成员还没填，渲染时回退到角色名。
    op.add_column("family_members", sa.Column("nickname", sa.String(length=60), nullable=True))


def downgrade() -> None:
    op.drop_column("family_members", "nickname")
    op.drop_column("accounts", "password_hash")
