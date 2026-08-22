locals {
  function_names = {
    producer = local.names.producer
    worker   = local.names.worker
  }

  # Cosmos data-plane RBAC uses its own /dbs/.../colls/... scope syntax rather
  # than the ARM sqlDatabases/.../containers/... resource ID.
  cosmos_orders_data_scope = "${azurerm_cosmosdb_account.main.id}/dbs/${azurerm_cosmosdb_sql_database.orders.name}/colls/${azurerm_cosmosdb_sql_container.orders.name}"
}

resource "azurerm_service_plan" "functions" {
  for_each = local.function_names

  name                = "plan-${each.key}-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.standard_tags
}

resource "azurerm_function_app_flex_consumption" "main" {
  for_each = local.function_names

  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions[each.key].id

  storage_container_type                         = "blobContainer"
  storage_container_endpoint                     = "https://${azurerm_storage_account.functions[each.key].name}.blob.core.windows.net/${local.deployment_containers[each.key]}"
  storage_authentication_type                    = "UserAssignedIdentity"
  storage_user_assigned_identity_id              = azurerm_user_assigned_identity.function_host[each.key].id
  runtime_name                                   = "python"
  runtime_version                                = "3.12"
  maximum_instance_count                         = var.function_maximum_instance_count
  instance_memory_in_mb                          = var.function_instance_memory_mb
  virtual_network_subnet_id                      = azurerm_subnet.functions.id
  public_network_access_enabled                  = false
  https_only                                     = true
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function_host[each.key].id]
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    http2_enabled                          = true
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version                = "1.2"
    ip_restriction_default_action          = "Deny"
    scm_ip_restriction_default_action      = "Deny"
  }

  app_settings = {
    AzureWebJobsStorage                           = ""
    AzureWebJobsStorage__accountName              = azurerm_storage_account.functions[each.key].name
    AzureWebJobsStorage__credential               = "managedidentity"
    AzureWebJobsStorage__clientId                 = azurerm_user_assigned_identity.function_host[each.key].client_id
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING     = "ClientId=${azurerm_user_assigned_identity.function_host[each.key].client_id};Authorization=AAD"
    API_CLIENT_TOKEN                              = "@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.main.name}.vault.azure.net/secrets/api-client-token/)"
    COSMOS_ENDPOINT                               = "@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.main.name}.vault.azure.net/secrets/cosmos-endpoint/)"
    COSMOS_DATABASE                               = azurerm_cosmosdb_sql_database.orders.name
    COSMOS_CONTAINER                              = azurerm_cosmosdb_sql_container.orders.name
    SERVICE_BUS_NAMESPACE_FQDN                    = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
    SERVICE_BUS_QUEUE_NAME                        = azurerm_servicebus_queue.orders.name
    WORKER_API_BASE_URL                           = "https://${local.names.worker}.azurewebsites.net"
    ServiceBusConnection__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
    ServiceBusConnection__credential              = "managedidentity"
  }

  tags = local.standard_tags

  depends_on = [
    azapi_resource.deployment_container,
    azapi_resource.key_vault_secret,
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.key_vault,
    azurerm_private_endpoint.service_bus,
    azurerm_private_endpoint.cosmos,
    azurerm_private_endpoint.monitor,
    azurerm_role_assignment.function_host_blob_owner,
    azurerm_role_assignment.function_host_table_contributor,
    azurerm_role_assignment.function_monitoring_publisher,
  ]
}

resource "azurerm_private_endpoint" "functions" {
  for_each = azurerm_function_app_flex_consumption.main

  name                = "pe-function-${each.key}-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-functions"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-function-${each.key}"
    private_connection_resource_id = each.value.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "functions"
    private_dns_zone_ids = [azurerm_private_dns_zone.main["functions"].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}

resource "azurerm_role_assignment" "service_bus_sender" {
  scope                = azurerm_servicebus_queue.orders.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_function_app_flex_consumption.main["producer"].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Flex currently resolves app-setting Key Vault references with the system
# identity. RBAC can be assigned only after the app creates that identity; the
# platform retries unresolved references while role assignment propagates.
resource "azurerm_role_assignment" "function_key_vault_secrets_user" {
  for_each = azurerm_function_app_flex_consumption.main

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "service_bus_receiver" {
  scope                = azurerm_servicebus_queue.orders.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_function_app_flex_consumption.main["worker"].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_cosmosdb_sql_role_assignment" "function_data_contributor" {
  for_each = azurerm_function_app_flex_consumption.main

  name                = uuidv5("url", "${local.cosmos_orders_data_scope}/${each.key}")
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = each.value.identity[0].principal_id
  scope               = local.cosmos_orders_data_scope
}
