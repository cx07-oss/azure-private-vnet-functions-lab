resource "azurerm_cosmosdb_account" "main" {
  name                          = local.names.cosmos
  resource_group_name           = azurerm_resource_group.main.name
  location                      = coalesce(var.cosmos_location, var.location)
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  local_authentication_enabled  = false
  public_network_access_enabled = false
  minimal_tls_version           = "Tls12"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = coalesce(var.cosmos_location, var.location)
    failover_priority = 0
  }

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  tags = local.standard_tags
}

resource "azurerm_cosmosdb_sql_database" "orders" {
  name                = local.cosmos_database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "orders" {
  name                  = local.cosmos_container_name
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.orders.name
  partition_key_paths   = ["/id"]
  partition_key_version = 2

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-cosmos-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-database"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.main["cosmos"].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}

locals {
  key_vault_secrets = {
    api-client-token = random_password.api_client_token.result
    # This is connection information for passwordless Cosmos access. No account
    # key exists because local authentication is disabled on the account.
    cosmos-endpoint = azurerm_cosmosdb_account.main.endpoint
  }
}

# The Key Vault provider resource is data-plane based. ARM child resources keep
# the initial deployment possible even though the vault is private from birth.
resource "azapi_resource" "key_vault_secret" {
  for_each = local.key_vault_secrets

  type      = "Microsoft.KeyVault/vaults/secrets@2025-05-01"
  name      = each.key
  parent_id = azurerm_key_vault.main.id

  body = {
    properties = {
      value = each.value
      attributes = {
        enabled = true
      }
    }
  }

  response_export_values = []
}
