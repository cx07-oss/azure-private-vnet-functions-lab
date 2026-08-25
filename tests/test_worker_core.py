from datetime import UTC, datetime

from vnetlab_worker.core import is_authorized, mark_processed


def test_mark_processed_adds_idempotency_fields() -> None:
    source = {"id": "order-1", "status": "submitted"}
    updated = mark_processed(
        source,
        message_id="message-1",
        now=datetime(2026, 8, 22, 1, 2, 3, tzinfo=UTC),
    )

    assert source == {"id": "order-1", "status": "submitted"}
    assert updated["status"] == "processed"
    assert updated["processedMessageId"] == "message-1"
    assert updated["processedAt"] == "2026-08-22T01:02:03+00:00"


def test_mark_processed_returns_same_document_for_duplicate_message() -> None:
    source = {
        "id": "order-1",
        "status": "processed",
        "processedMessageId": "message-1",
    }

    assert mark_processed(source, message_id="message-1") is source


def test_worker_token_authentication() -> None:
    assert is_authorized({"x-vnetlab-token": "secret"}, "secret")
    assert not is_authorized({"x-vnetlab-token": "wrong"}, "secret")
