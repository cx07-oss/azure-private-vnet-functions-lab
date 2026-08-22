resource "azurerm_servicebus_namespace" "main" {
  name                          = local.names.service_bus
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = "Premium"
  capacity                      = 1
  premium_messaging_partitions  = 1
  minimum_tls_version           = "1.2"
  local_auth_enabled            = false
  public_network_access_enabled = false
  tags                          = local.standard_tags
}

resource "azurerm_servicebus_queue" "orders" {
  name                                    = local.service_bus_queue
  namespace_id                            = azurerm_servicebus_namespace.main.id
  max_size_in_megabytes                   = 1024
  lock_duration                           = "PT5M"
  max_delivery_count                      = 10
  dead_lettering_on_message_expiration    = true
  default_message_ttl                     = "P14D"
  duplicate_detection_history_time_window = "PT10M"
  requires_duplicate_detection            = true
}

resource "azurerm_private_endpoint" "service_bus" {
  name                = "pe-servicebus-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-servicebus"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-servicebus"
    private_connection_resource_id = azurerm_servicebus_namespace.main.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "servicebus"
    private_dns_zone_ids = [azurerm_private_dns_zone.main["servicebus"].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}
