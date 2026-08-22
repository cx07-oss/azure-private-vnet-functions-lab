from __future__ import annotations

import hmac
import uuid
from collections.abc import Mapping
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Any


class ValidationError(ValueError):
    """Raised when an API order is invalid."""


def is_authorized(headers: Mapping[str, str], expected_token: str) -> bool:
    supplied = headers.get("x-vnetlab-token", "")
    return bool(supplied) and hmac.compare_digest(supplied, expected_token)


def build_order(payload: Any, *, now: datetime | None = None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValidationError("The request body must be a JSON object.")

    raw_customer_id = payload.get("customerId")
    if not isinstance(raw_customer_id, str):
        raise ValidationError("customerId is required and must be a string.")
    customer_id = raw_customer_id.strip()
    if not customer_id or len(customer_id) > 100:
        raise ValidationError("customerId is required and must be at most 100 characters.")

    try:
        amount = Decimal(str(payload.get("amount")))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValidationError("amount must be a decimal number.") from exc
    if not amount.is_finite() or amount <= 0 or amount > Decimal("1000000"):
        raise ValidationError("amount must be greater than 0 and at most 1000000.")
    try:
        rounded_amount = amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    except InvalidOperation as exc:
        raise ValidationError("amount must have a supported decimal precision.") from exc
    if rounded_amount <= 0:
        raise ValidationError("amount must round to at least 0.01.")

    raw_description = payload.get("description", "")
    if raw_description is None:
        raw_description = ""
    if not isinstance(raw_description, str):
        raise ValidationError("description must be a string when supplied.")
    description = raw_description.strip()
    if len(description) > 500:
        raise ValidationError("description must be at most 500 characters.")

    order_id = str(uuid.uuid4())
    timestamp = (now or datetime.now(UTC)).isoformat()
    return {
        "id": order_id,
        "customerId": customer_id,
        "amount": str(rounded_amount),
        "description": description,
        "status": "submitted",
        "createdAt": timestamp,
        "updatedAt": timestamp,
        "messageId": order_id,
    }
