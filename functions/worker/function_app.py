from __future__ import annotations

import json
import logging

import azure.functions as func
from worker.adapters import OrderNotFoundError, OrderRepository
from worker.config import Settings
from worker.core import is_authorized, mark_processed

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def json_response(payload: dict, status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload, separators=(",", ":")),
        status_code=status_code,
        mimetype="application/json",
    )


@app.service_bus_queue_trigger(
    arg_name="message",
    queue_name="%SERVICE_BUS_QUEUE_NAME%",
    connection="ServiceBusConnection",
)
def process_order(message: func.ServiceBusMessage) -> None:
    settings = Settings.from_environment(require_api_token=False)
    payload = json.loads(message.get_body().decode("utf-8"))
    order_id = str(payload["id"])
    message_id = str(message.message_id or payload.get("messageId") or order_id)

    repository = OrderRepository(settings)
    order = repository.get(order_id)
    updated = mark_processed(order, message_id=message_id)
    if updated is order:
        logging.info("Order %s was already processed by message %s", order_id, message_id)
        return

    repository.replace(updated)
    logging.info("Processed order %s from Service Bus message %s", order_id, message_id)


@app.route(route="health", methods=["GET"])
def health(_: func.HttpRequest) -> func.HttpResponse:
    try:
        settings = Settings.from_environment()
        return json_response(
            {
                "app": "worker",
                "scope": "configuration",
                "status": "ok" if settings.key_vault_references_resolved else "degraded",
                "keyVaultReferencesResolved": settings.key_vault_references_resolved,
            },
            200 if settings.key_vault_references_resolved else 503,
        )
    except RuntimeError as exc:
        return json_response({"app": "worker", "status": "degraded", "error": str(exc)}, 503)


@app.route(route="orders/{order_id}", methods=["GET"])
def get_order(req: func.HttpRequest) -> func.HttpResponse:
    try:
        settings = Settings.from_environment()
    except RuntimeError:
        logging.exception("Function configuration is incomplete")
        return json_response({"error": "Service configuration is incomplete."}, 503)

    if not settings.key_vault_references_resolved:
        return json_response({"error": "Key Vault references have not resolved yet."}, 503)
    if not is_authorized(req.headers, settings.api_client_token):
        return json_response({"error": "Unauthorized."}, 401)

    order_id = str(req.route_params.get("order_id", "")).strip()
    if not order_id:
        return json_response({"error": "order_id is required."}, 400)

    try:
        order = OrderRepository(settings).get(order_id)
    except OrderNotFoundError:
        return json_response({"error": "Order not found.", "orderId": order_id}, 404)
    except Exception:
        logging.exception("Failed to read order %s", order_id)
        return json_response({"error": "The order could not be read."}, 502)
    return json_response(order, 200)
