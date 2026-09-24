"""replace items.is_done with a three-state status

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-24

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "items",
        sa.Column("status", sa.String(length=20), server_default="todo", nullable=False),
    )
    op.execute("UPDATE items SET status = 'done' WHERE is_done")
    op.create_check_constraint(
        "ck_items_status", "items", "status IN ('todo', 'in_progress', 'done')"
    )
    op.drop_column("items", "is_done")


def downgrade() -> None:
    op.add_column(
        "items",
        sa.Column("is_done", sa.Boolean(), server_default="false", nullable=False),
    )
    op.execute("UPDATE items SET is_done = (status = 'done')")
    op.drop_constraint("ck_items_status", "items", type_="check")
    op.drop_column("items", "status")
