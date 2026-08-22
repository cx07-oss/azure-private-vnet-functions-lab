resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.standard_tags
}

resource "azurerm_bastion_host" "main" {
  name                   = "bas-${local.stem}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  sku                    = "Standard"
  copy_paste_enabled     = true
  file_copy_enabled      = true
  ip_connect_enabled     = true
  shareable_link_enabled = false
  tunneling_enabled      = true
  scale_units            = 2
  tags                   = local.standard_tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_network_interface" "management" {
  name                           = "nic-${local.names.vm}"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = azurerm_resource_group.main.location
  accelerated_networking_enabled = false
  ip_forwarding_enabled          = false
  tags                           = local.standard_tags

  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "management" {
  name                            = local.names.vm
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.management_vm_size
  admin_username                  = var.management_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.management.id]
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  patch_assessment_mode           = "AutomaticByPlatform"
  patch_mode                      = "AutomaticByPlatform"
  tags                            = local.standard_tags

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.management_admin_username
    public_key = trimspace(var.management_ssh_public_key)
  }

  os_disk {
    name                 = "osdisk-${local.names.vm}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_username      = var.management_admin_username
    resource_group_name = azurerm_resource_group.main.name
    producer_app_name   = azurerm_function_app_flex_consumption.main["producer"].name
    worker_app_name     = azurerm_function_app_flex_consumption.main["worker"].name
    key_vault_name      = azurerm_key_vault.main.name
    storage_blob_fqdn   = "${azurerm_storage_account.functions["producer"].name}.blob.core.windows.net"
    service_bus_fqdn    = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
    cosmos_fqdn         = trimsuffix(trimprefix(azurerm_cosmosdb_account.main.endpoint, "https://"), "/")
    key_vault_fqdn      = "${azurerm_key_vault.main.name}.vault.azure.net"
  }))

  depends_on = [
    azurerm_private_endpoint.functions,
    azurerm_private_endpoint.key_vault,
    azurerm_subnet_nat_gateway_association.management,
  ]
}

resource "azurerm_role_assignment" "management_vm_key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.management.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# The VM is the lab's management and diagnostic workstation. Reader permits
# control-plane inspection without mutation; data-plane access remains governed
# by the narrowly scoped roles below.
resource "azurerm_role_assignment" "management_vm_resource_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.management.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "management_vm_log_analytics_reader" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_linux_virtual_machine.management.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "management_vm_function_deployer" {
  for_each = azurerm_function_app_flex_consumption.main

  scope                = each.value.id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_linux_virtual_machine.management.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_monitor_data_collection_rule" "management_vm" {
  name                        = "dcr-management-${local.stem}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.management_vm.id
  tags                        = local.standard_tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "law"
    }
  }

  data_sources {
    performance_counter {
      name                          = "linux-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes Memory",
        "\\Logical Disk(*)\\% Used Space",
      ]
    }

    syslog {
      name           = "linux-syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["law"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "management_vm" {
  name                    = "dcra-management-${local.stem}"
  target_resource_id      = azurerm_linux_virtual_machine.management.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.management_vm.id
  description             = "Collect management VM performance and security-relevant syslog events."
}

resource "azurerm_monitor_data_collection_rule_association" "management_vm_endpoint" {
  target_resource_id          = azurerm_linux_virtual_machine.management.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.management_vm.id
  description                 = "Use the private DCE for Azure Monitor Agent configuration and ingestion."
}

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.management.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  automatic_upgrade_enabled  = true
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_monitor_data_collection_rule_association.management_vm,
    azurerm_monitor_data_collection_rule_association.management_vm_endpoint,
    azurerm_private_endpoint.monitor,
  ]
}
