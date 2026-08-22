resource "azurerm_log_analytics_workspace" "main" {
  name                         = local.names.law
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  local_authentication_enabled = false
  internet_ingestion_enabled   = false
  internet_query_enabled       = false
  tags                         = local.standard_tags
}

resource "azurerm_application_insights" "main" {
  name                         = local.names.app_insights
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  workspace_id                 = azurerm_log_analytics_workspace.main.id
  application_type             = "web"
  local_authentication_enabled = false
  internet_ingestion_enabled   = false
  internet_query_enabled       = false
  retention_in_days            = 90
  tags                         = local.standard_tags
}

resource "azurerm_monitor_data_collection_endpoint" "management_vm" {
  name                          = "dce-management-${local.stem}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  kind                          = "Linux"
  public_network_access_enabled = false
  description                   = "Private configuration and ingestion endpoint for the management VM Azure Monitor Agent."
  tags                          = local.standard_tags
}

resource "azurerm_monitor_private_link_scope" "main" {
  name                  = "ampls-${local.stem}"
  resource_group_name   = azurerm_resource_group.main.name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"
  tags                  = local.standard_tags
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  name                = "ampls-law-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  scope_name          = azurerm_monitor_private_link_scope.main.name
  linked_resource_id  = azurerm_log_analytics_workspace.main.id
}

resource "azurerm_monitor_private_link_scoped_service" "application_insights" {
  name                = "ampls-appi-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  scope_name          = azurerm_monitor_private_link_scope.main.name
  linked_resource_id  = azurerm_application_insights.main.id
}

resource "azurerm_monitor_private_link_scoped_service" "data_collection_endpoint" {
  name                = "ampls-dce-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  scope_name          = azurerm_monitor_private_link_scope.main.name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.management_vm.id
}

resource "azurerm_private_endpoint" "monitor" {
  name                = "pe-monitor-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-monitor"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-monitor"
    private_connection_resource_id = azurerm_monitor_private_link_scope.main.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "azuremonitor"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.main["monitor"].id,
      azurerm_private_dns_zone.main["oms"].id,
      azurerm_private_dns_zone.main["ods"].id,
      azurerm_private_dns_zone.main["agentsvc"].id,
      azurerm_private_dns_zone.main["blob"].id,
    ]
  }

  depends_on = [
    azurerm_monitor_private_link_scoped_service.log_analytics,
    azurerm_monitor_private_link_scoped_service.application_insights,
    azurerm_monitor_private_link_scoped_service.data_collection_endpoint,
    azurerm_subnet_network_security_group_association.private_endpoints,
  ]
}

resource "azurerm_role_assignment" "function_monitoring_publisher" {
  for_each = azurerm_user_assigned_identity.function_host

  scope                = azurerm_application_insights.main.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}
