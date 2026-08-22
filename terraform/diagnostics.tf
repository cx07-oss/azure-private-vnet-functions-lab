module "diagnostics_subscription_activity" {
  count  = var.enable_subscription_activity_diagnostics ? 1 : 0
  source = "./modules/diagnostic-setting"

  name                       = "diag-subscription-activity"
  target_resource_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_vnet" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-vnet"
  target_resource_id         = azurerm_virtual_network.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_nsg_functions" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-nsg-functions"
  target_resource_id         = azurerm_network_security_group.functions.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_nsg_management" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-nsg-management"
  target_resource_id         = azurerm_network_security_group.management.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_nsg_private_endpoints" {
  for_each = azurerm_network_security_group.private_endpoints
  source   = "./modules/diagnostic-setting"

  name                       = "diag-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_storage_accounts" {
  for_each = azurerm_storage_account.functions
  source   = "./modules/diagnostic-setting"

  name                       = "diag-storage-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

locals {
  storage_diagnostic_services = {
    for pair in setproduct(keys(local.deployment_containers), ["blob", "queue", "table"]) :
    "${pair[0]}-${pair[1]}" => {
      app          = pair[0]
      service_path = pair[1] == "blob" ? "blobServices/default" : pair[1] == "queue" ? "queueServices/default" : "tableServices/default"
    }
  }
}

module "diagnostics_storage_services" {
  for_each = local.storage_diagnostic_services
  source   = "./modules/diagnostic-setting"

  name                       = "diag-storage-${each.key}"
  target_resource_id         = "${azurerm_storage_account.functions[each.value.app].id}/${each.value.service_path}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  depends_on = [azapi_resource.deployment_container]
}

module "diagnostics_key_vault" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-keyvault"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_service_bus" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-servicebus"
  target_resource_id         = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_cosmos" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-cosmos"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_functions" {
  for_each = azurerm_function_app_flex_consumption.main
  source   = "./modules/diagnostic-setting"

  name                       = "diag-function-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_function_plans" {
  for_each = azurerm_service_plan.functions
  source   = "./modules/diagnostic-setting"

  name                       = "diag-plan-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_management_vm" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-management-vm"
  target_resource_id         = azurerm_linux_virtual_machine.management.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

module "diagnostics_bastion" {
  source = "./modules/diagnostic-setting"

  name                       = "diag-bastion"
  target_resource_id         = azurerm_bastion_host.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}
