from __future__ import annotations

import json
from typing import Any

from .config import Settings


def azure_credential():
    # DefaultAzureCredential uses the Function system-assigned identity in Azure
    # and Azure CLI/developer credentials during local development.
    from azure.identity import DefaultAzureCredential

    return DefaultAzureCredential()


class OrderRepository:
    def __init__(self, settings: Settings, credential: Any | None = None) -> None:
        from azure.cosmos import CosmosClient

        client = CosmosClient(settings.cosmos_endpoint, credential=credential or azure_credential())
        database = client.get_database_client(settings.cosmos_database)
        self._container = database.get_container_client(settings.cosmos_container)

    def create(self, order: dict[str, Any]) -> None:
        self._container.create_item(body=order)


class OrderPublisher:
    def __init__(self, settings: Settings, credential: Any | None = None) -> None:
        from azure.servicebus import ServiceBusClient

        self._queue_name = settings.service_bus_queue
        self._client = ServiceBusClient(
            fully_qualified_namespace=settings.service_bus_namespace,
            credential=credential or azure_credential(),
            logging_enable=False,
        )

    def send(self, order: dict[str, Any]) -> None:
        from azure.servicebus import ServiceBusMessage

        message = ServiceBusMessage(
            json.dumps(order, separators=(",", ":")),
            message_id=order["messageId"],
            content_type="application/json",
            correlation_id=order["id"],
        )
        with (
            self._client,
            self._client.get_queue_sender(queue_name=self._queue_name) as sender,
        ):
            sender.send_messages(message)
