"""Runtime configuration for the order worker."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    cosmos_endpoint: str
    cosmos_database: str
    cosmos_container: str
    api_client_token: str

    @classmethod
    def from_environment(cls, *, require_api_token: bool = True) -> Settings:
        names = {
            "cosmos_endpoint": "COSMOS_ENDPOINT",
            "cosmos_database": "COSMOS_DATABASE",
            "cosmos_container": "COSMOS_CONTAINER",
        }
        if require_api_token:
            names["api_client_token"] = "API_CLIENT_TOKEN"
        values = {field: os.getenv(variable, "").strip() for field, variable in names.items()}
        missing = [variable for field, variable in names.items() if not values[field]]
        if missing:
            raise RuntimeError(f"Missing required app settings: {', '.join(sorted(missing))}")
        values.setdefault("api_client_token", "")
        return cls(**values)

    @property
    def key_vault_references_resolved(self) -> bool:
        values = (self.cosmos_endpoint, self.api_client_token)
        return all(not value.startswith("@Microsoft.KeyVault(") for value in values)
