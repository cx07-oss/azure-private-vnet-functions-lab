resource "azurerm_key_vault" "main" {
  name                          = local.names.key_vault
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }

  tags = local.standard_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-keyvault-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints["pe-keyvault"].id
  tags                = local.standard_tags

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "keyvault"
    private_dns_zone_ids = [azurerm_private_dns_zone.main["keyvault"].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}

resource "random_password" "api_client_token" {
  length           = 48
  special          = true
  override_special = "-_.~"
}
