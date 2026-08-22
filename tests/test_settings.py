from producer.config import Settings as ProducerSettings
from worker.config import Settings as WorkerSettings


def test_producer_detects_unresolved_key_vault_reference() -> None:
    settings = ProducerSettings(
        cosmos_endpoint="@Microsoft.KeyVault(SecretUri=example)",
        cosmos_database="orders",
        cosmos_container="orders",
        service_bus_namespace="example.servicebus.windows.net",
        service_bus_queue="orders",
        worker_api_base_url="https://worker.azurewebsites.net",
        api_client_token="resolved",
    )
    assert not settings.key_vault_references_resolved


def test_worker_accepts_resolved_key_vault_values() -> None:
    settings = WorkerSettings(
        cosmos_endpoint="https://example.documents.azure.com:443/",
        cosmos_database="orders",
        cosmos_container="orders",
        api_client_token="resolved",
    )
    assert settings.key_vault_references_resolved


def test_worker_background_settings_do_not_require_api_token(monkeypatch) -> None:
    monkeypatch.setenv("COSMOS_ENDPOINT", "https://example.documents.azure.com:443/")
    monkeypatch.setenv("COSMOS_DATABASE", "orders")
    monkeypatch.setenv("COSMOS_CONTAINER", "orders")
    monkeypatch.delenv("API_CLIENT_TOKEN", raising=False)

    settings = WorkerSettings.from_environment(require_api_token=False)

    assert settings.api_client_token == ""
