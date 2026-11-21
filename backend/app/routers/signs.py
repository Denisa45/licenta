"""/signs: lecțiile, în ordinea din drumul de învățare."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Sign, User
from ..schemas import SignSchema
from ..security import current_user

router = APIRouter(prefix="/signs", tags=["signs"])


@router.get("", response_model=list[SignSchema])
def list_signs(db: Session = Depends(get_db), _: User = Depends(current_user)):
    return db.scalars(select(Sign).order_by(Sign.sort_order, Sign.id)).all()


@router.get("/{sign_id}", response_model=SignSchema)
def get_sign(sign_id: str, db: Session = Depends(get_db), _: User = Depends(current_user)):
    sign = db.get(Sign, sign_id)
    if sign is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="sign-not-found")
    return sign
