resource "azurerm_user_assigned_identity" "function_host" {
  for_each = local.deployment_containers

  name                = "id-${each.key}-host-${local.stem}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.standard_tags
}
