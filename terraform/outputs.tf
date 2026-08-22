output "resource_group_name" {
  description = "Resource group containing the lab."
  value       = azurerm_resource_group.main.name
}
output "vnet_id" {
  description = "Lab virtual network resource ID."
  value       = azurerm_virtual_network.main.id
}

output "function_app_names" {
  description = "Private Function App names."
  value       = { for key, app in azurerm_function_app_flex_consumption.main : key => app.name }
}

output "function_private_urls" {
  description = "Function URLs. They resolve privately only from the VNet or connected networks."
  value = {
    producer_health = "https://${azurerm_function_app_flex_consumption.main["producer"].name}.azurewebsites.net/api/health"
    producer_orders = "https://${azurerm_function_app_flex_consumption.main["producer"].name}.azurewebsites.net/api/orders"
    worker_health   = "https://${azurerm_function_app_flex_consumption.main["worker"].name}.azurewebsites.net/api/health"
    worker_orders   = "https://${azurerm_function_app_flex_consumption.main["worker"].name}.azurewebsites.net/api/orders/{orderId}"
  }
}

output "management_vm" {
  description = "Private management VM connection details."
  value = {
    id         = azurerm_linux_virtual_machine.management.id
    name       = azurerm_linux_virtual_machine.management.name
    private_ip = azurerm_network_interface.management.private_ip_address
    username   = var.management_admin_username
  }
}

output "bastion" {
  description = "Bastion details. Its public IP is the lab's deliberate management-plane ingress exception."
  value = {
    name      = azurerm_bastion_host.main.name
    public_ip = azurerm_public_ip.bastion.ip_address
  }
}

output "private_service_names" {
  description = "Names used by validation and management scripts."
  value = {
    key_vault        = azurerm_key_vault.main.name
    service_bus      = azurerm_servicebus_namespace.main.name
    cosmos           = azurerm_cosmosdb_account.main.name
    storage_producer = azurerm_storage_account.functions["producer"].name
    storage_worker   = azurerm_storage_account.functions["worker"].name
    log_analytics    = azurerm_log_analytics_workspace.main.name
  }
}

output "bastion_tunnel_command" {
  description = "Open an SSH tunnel, then connect to 127.0.0.1:2222 with the matching private key."
  value       = "az network bastion tunnel --name ${azurerm_bastion_host.main.name} --resource-group ${azurerm_resource_group.main.name} --target-resource-id ${azurerm_linux_virtual_machine.management.id} --resource-port 22 --port 2222"
}
