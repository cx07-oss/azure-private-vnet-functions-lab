from __future__ import annotations

import json
import logging

import azure.functions as func
from producer.adapters import OrderPublisher, OrderRepository
from producer.config import Settings
from producer.core import build_order, is_authorized

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def json_response(payload: dict, status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload, separators=(",", ":")),
        status_code=status_code,
        mimetype="application/json",
    )


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    try:
        settings = Settings.from_environment()
        return json_response(
            {
                "app": "producer",
                "scope": "configuration",
                "status": "ok" if settings.key_vault_references_resolved else "degraded",
                "keyVaultReferencesResolved": settings.key_vault_references_resolved,
            },
            200 if settings.key_vault_references_resolved else 503,
        )
    except RuntimeError as exc:
        return json_response({"app": "producer", "status": "degraded", "error": str(exc)}, 503)


@app.route(route="orders", methods=["POST"])
def create_order(req: func.HttpRequest) -> func.HttpResponse:
    try:
        settings = Settings.from_environment()
    except RuntimeError:
        logging.exception("Function configuration is incomplete")
        return json_response({"error": "Service configuration is incomplete."}, 503)

    if not settings.key_vault_references_resolved:
        return json_response({"error": "Key Vault references have not resolved yet."}, 503)
    if not is_authorized(req.headers, settings.api_client_token):
        return json_response({"error": "Unauthorized."}, 401)

    try:
        order = build_order(req.get_json())
    except ValueError as exc:
        return json_response({"error": str(exc)}, 400)

    repository = OrderRepository(settings)
    publisher = OrderPublisher(settings)
    try:
        repository.create(order)
        publisher.send(order)
    except Exception:
        logging.exception("Failed to persist or publish order %s", order["id"])
        return json_response(
            {"error": "The order could not be submitted.", "orderId": order["id"]}, 502
        )

    logging.info("Submitted order %s with message %s", order["id"], order["messageId"])
    return json_response(
        {
            "orderId": order["id"],
            "status": order["status"],
            "statusUrl": f"{settings.worker_api_base_url}/api/orders/{order['id']}",
        },
        202,
    )
