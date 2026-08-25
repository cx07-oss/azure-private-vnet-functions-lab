"""Azure adapters used by the order worker."""

from __future__ import annotations

from typing import Any

from .config import Settings


class OrderNotFoundError(LookupError):
    pass


def azure_credential():
    from azure.identity import DefaultAzureCredential

    return DefaultAzureCredential()


class OrderRepository:
    def __init__(self, settings: Settings, credential: Any | None = None) -> None:
        from azure.cosmos import CosmosClient

        client = CosmosClient(settings.cosmos_endpoint, credential=credential or azure_credential())
        database = client.get_database_client(settings.cosmos_database)
        self._container = database.get_container_client(settings.cosmos_container)

    def get(self, order_id: str) -> dict[str, Any]:
        from azure.cosmos.exceptions import CosmosResourceNotFoundError

        try:
            return self._container.read_item(item=order_id, partition_key=order_id)
        except CosmosResourceNotFoundError as exc:
            raise OrderNotFoundError(order_id) from exc

    def replace(self, order: dict[str, Any]) -> None:
        self._container.replace_item(item=order["id"], body=order)
