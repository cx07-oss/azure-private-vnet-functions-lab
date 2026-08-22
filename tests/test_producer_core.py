from datetime import UTC, datetime

import pytest
from producer.core import ValidationError, build_order, is_authorized


def test_build_order_normalizes_values() -> None:
    now = datetime(2026, 8, 22, 1, 2, 3, tzinfo=UTC)
    order = build_order(
        {"customerId": " customer-1 ", "amount": "12.3", "description": "sample"},
        now=now,
    )

    assert order["customerId"] == "customer-1"
    assert order["amount"] == "12.30"
    assert order["status"] == "submitted"
    assert order["messageId"] == order["id"]
    assert order["createdAt"] == "2026-08-22T01:02:03+00:00"


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"customerId": None, "amount": 1},
        {"customerId": {"nested": "value"}, "amount": 1},
        {"customerId": "x", "amount": 0},
        {"customerId": "x", "amount": "NaN"},
        {"customerId": "x", "amount": "Infinity"},
        {"customerId": "x", "amount": "1e-999999"},
        {"customerId": "x", "amount": "not-a-number"},
        {"customerId": "x", "amount": 1, "description": ["not", "text"]},
        {"customerId": "x", "amount": 1, "description": "x" * 501},
    ],
)
def test_build_order_rejects_invalid_payload(payload: dict) -> None:
    with pytest.raises(ValidationError):
        build_order(payload)


def test_token_authentication_is_exact() -> None:
    assert is_authorized({"x-vnetlab-token": "secret"}, "secret")
    assert not is_authorized({"x-vnetlab-token": "Secret"}, "secret")
    assert not is_authorized({}, "secret")


def test_null_description_is_treated_as_empty() -> None:
    order = build_order({"customerId": "x", "amount": "0.005", "description": None})

    assert order["amount"] == "0.01"
    assert order["description"] == ""
