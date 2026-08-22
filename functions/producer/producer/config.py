from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    cosmos_endpoint: str
    cosmos_database: str
    cosmos_container: str
    service_bus_namespace: str
    service_bus_queue: str
    worker_api_base_url: str
    api_client_token: str

    @classmethod
    def from_environment(cls) -> Settings:
        names = {
            "cosmos_endpoint": "COSMOS_ENDPOINT",
            "cosmos_database": "COSMOS_DATABASE",
            "cosmos_container": "COSMOS_CONTAINER",
            "service_bus_namespace": "SERVICE_BUS_NAMESPACE_FQDN",
            "service_bus_queue": "SERVICE_BUS_QUEUE_NAME",
            "worker_api_base_url": "WORKER_API_BASE_URL",
            "api_client_token": "API_CLIENT_TOKEN",
        }
        values = {field: os.getenv(variable, "").strip() for field, variable in names.items()}
        missing = [variable for field, variable in names.items() if not values[field]]
        if missing:
            raise RuntimeError(f"Missing required app settings: {', '.join(sorted(missing))}")
        return cls(**values)

    @property
    def key_vault_references_resolved(self) -> bool:
        values = (self.cosmos_endpoint, self.api_client_token)
        return all(not value.startswith("@Microsoft.KeyVault(") for value in values)
