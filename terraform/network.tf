resource "azurerm_resource_group" "main" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.standard_tags
}

resource "azurerm_virtual_network" "main" {
  name                = local.names.vnet
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.42.0.0/16"]
  tags                = local.standard_tags
}

resource "azurerm_network_security_group" "functions" {
  name                = "nsg-functions-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.standard_tags
}

resource "azurerm_subnet" "functions" {
  name                 = "snet-functions"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.subnets.functions.address_prefix]

  delegation {
    name = "flex-consumption"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "functions" {
  subnet_id                 = azurerm_subnet.functions.id
  network_security_group_id = azurerm_network_security_group.functions.id
}

resource "azurerm_network_security_group" "management" {
  name                = "nsg-management-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.standard_tags
}

resource "azurerm_network_security_rule" "management_ssh_from_bastion" {
  name                        = "AllowSshFromBastion"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "10.42.2.0/26"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.management.name
}

resource "azurerm_network_security_rule" "management_deny_other_vnet" {
  name                        = "DenyOtherVnetInbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.management.name
}

resource "azurerm_subnet" "management" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.subnets.management.address_prefix]
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.42.2.0/26"]
}

resource "azurerm_network_security_group" "private_endpoints" {
  for_each = {
    for name, config in local.subnets : name => config
    if startswith(name, "pe-")
  }

  name                = "nsg-${each.key}-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.standard_tags
}

resource "azurerm_network_security_rule" "private_endpoints_from_workloads" {
  for_each = azurerm_network_security_group.private_endpoints

  name                        = "AllowHttpsFromWorkloads"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = each.key == "pe-servicebus" ? ["443", "5671"] : ["443"]
  source_address_prefixes     = [local.subnets.functions.address_prefix, local.subnets.management.address_prefix]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = each.value.name
}

resource "azurerm_network_security_rule" "private_endpoints_deny_other_vnet" {
  for_each = azurerm_network_security_group.private_endpoints

  name                        = "DenyOtherVnetInbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = each.value.name
}

resource "azurerm_subnet" "private_endpoints" {
  for_each = {
    for name, config in local.subnets : name => config
    if startswith(name, "pe-")
  }

  name                              = "snet-${each.key}"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  for_each = azurerm_subnet.private_endpoints

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.private_endpoints[each.key].id
}

resource "azurerm_private_dns_zone" "main" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.standard_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  for_each = azurerm_private_dns_zone.main

  name                  = "link-${each.key}-${local.stem}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.standard_tags
}
