resource "azurerm_storage_account" "functions" {
  for_each = {
    producer = local.names.storage_producer
    worker   = local.names.storage_worker
  }

  name                             = each.value
  resource_group_name              = azurerm_resource_group.main.name
  location                         = azurerm_resource_group.main.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  public_network_access_enabled    = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  tags = local.standard_tags
}

# The azurerm_storage_container resource uses the Storage data plane. These ARM
# child resources can be created while shared-key and public access are disabled.
resource "azapi_resource" "deployment_container" {
  for_each = azurerm_storage_account.functions

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01"
  name      = local.deployment_containers[each.key]
  parent_id = "${each.value.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_role_assignment" "function_host_blob_owner" {
  for_each = azurerm_storage_account.functions

  scope                = each.value.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.function_host[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "function_host_table_contributor" {
  for_each = azurerm_storage_account.functions

  scope                = each.value.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function_host[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

locals {
  storage_private_endpoints = {
    for pair in setproduct(keys(local.deployment_containers), ["blob", "queue", "table"]) :
    "${pair[0]}-${pair[1]}" => {
      app     = pair[0]
      service = pair[1]
    }
  }
}

resource "azurerm_private_endpoint" "storage" {
  for_each = local.storage_private_endpoints

  name                = "pe-${each.key}-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-storage"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = azurerm_storage_account.functions[each.value.app].id
    subresource_names              = [each.value.service]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "storage-${each.value.service}"
    private_dns_zone_ids = [azurerm_private_dns_zone.main[each.value.service].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}
