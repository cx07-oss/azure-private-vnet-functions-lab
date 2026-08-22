from __future__ import annotations

import hmac
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any


def is_authorized(headers: Mapping[str, str], expected_token: str) -> bool:
    supplied = headers.get("x-vnetlab-token", "")
    return bool(supplied) and hmac.compare_digest(supplied, expected_token)


def mark_processed(
    order: dict[str, Any], *, message_id: str, now: datetime | None = None
) -> dict[str, Any]:
    if order.get("status") == "processed" and order.get("processedMessageId") == message_id:
        return order

    updated = dict(order)
    timestamp = (now or datetime.now(UTC)).isoformat()
    updated.update(
        {
            "status": "processed",
            "processedAt": timestamp,
            "updatedAt": timestamp,
            "processedMessageId": message_id,
        }
    )
    return updated
