from fastapi import APIRouter, HTTPException, status
from sqlalchemy import text

from app.db import SessionDep

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/ready", summary="Readiness probe")
async def ready(session: SessionDep) -> dict[str, str]:
    """Report readiness, including whether the database answers."""
    try:
        await session.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001 - any failure means "not ready"
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unavailable",
        ) from exc
    return {"status": "ok", "database": "ok"}
