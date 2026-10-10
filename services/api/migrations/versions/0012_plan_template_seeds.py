"""Plan template seeds: which templates each plan has ever generated."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0012_plan_template_seeds"
down_revision = "0011_family_events"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 记的是「生成过」而不是「现在还在」：用户删掉的模板任务不会因孕周推进而复活。
    op.create_table(
        "plan_template_seeds",
        sa.Column(
            "plan_id",
            sa.Uuid(),
            sa.ForeignKey("pregnancy_plans.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("template_id", sa.String(160), nullable=False),
        sa.Column("seeded_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("plan_id", "template_id"),
    )
    # 回填：已有计划里的模板任务都算生成过。已被删掉的那些找不回来了，
    # 它们在当前孕周仍适用时会再生成一次——只影响上线前删过模板任务的计划。
    op.execute(
        """
        INSERT INTO plan_template_seeds (plan_id, template_id, seeded_at)
        SELECT plan_id, source_id, created_at FROM tasks
        WHERE source_type = 'template' AND source_id IS NOT NULL
        ON CONFLICT DO NOTHING
        """
    )


def downgrade() -> None:
    op.drop_table("plan_template_seeds")
