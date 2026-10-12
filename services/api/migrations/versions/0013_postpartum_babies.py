"""产后阶段与可归档的宝宝档案，现有孕期继续使用原有数据。"""
import sqlalchemy as sa
from alembic import op

revision = "0013_postpartum_babies"
down_revision = "0012_plan_template_seeds"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("pregnancies", sa.Column("birth_date", sa.Date(), nullable=True))
    op.add_column("pregnancies", sa.Column("birth_revision", sa.Uuid(), nullable=True))
    op.create_table("babies",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("pregnancy_id", sa.Uuid(), sa.ForeignKey("pregnancies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("birth_revision", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=False),
        sa.Column("sex", sa.String(10), nullable=False),
        sa.Column("birth_weight_grams", sa.Integer(), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_babies_pregnancy_active", "babies", ["pregnancy_id", "archived_at"])


def downgrade():
    op.drop_table("babies")
    op.drop_column("pregnancies", "birth_revision")
    op.drop_column("pregnancies", "birth_date")
