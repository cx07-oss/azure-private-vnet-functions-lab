mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      client_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "33333333-3333-3333-3333-333333333333"
      tenant_id       = "44444444-4444-4444-4444-444444444444"
    }
  }

  mock_data "azurerm_monitor_diagnostic_categories" {
    defaults = {
      log_category_types = ["AuditEvent"]
      metrics            = ["AllMetrics"]
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      client_id    = "55555555-5555-5555-5555-555555555555"
      id           = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock"
      principal_id = "66666666-6666-6666-6666-666666666666"
    }
  }

  mock_resource "azurerm_function_app_flex_consumption" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Web/sites/function-mock"
      identity = {
        principal_id = "77777777-7777-7777-7777-777777777777"
        tenant_id    = "44444444-4444-4444-4444-444444444444"
      }
    }
  }

  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Compute/virtualMachines/vm-mock"
      identity = {
        principal_id = "88888888-8888-8888-8888-888888888888"
        tenant_id    = "44444444-4444-4444-4444-444444444444"
      }
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/subnet-mock"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/networkSecurityGroups/nsg-mock"
    }
  }

  mock_resource "azurerm_network_interface" {
    defaults = {
      id                 = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/networkInterfaces/nic-mock"
      private_ip_address = "10.42.1.4"
    }
  }

  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/publicIPAddresses/pip-mock"
      ip_address = "203.0.113.10"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/privateDnsZones/privatelink.example.test"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Storage/storageAccounts/stmock"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.KeyVault/vaults/kv-mock"
    }
  }

  mock_resource "azurerm_servicebus_namespace" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.ServiceBus/namespaces/sb-mock"
    }
  }

  mock_resource "azurerm_servicebus_queue" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.ServiceBus/namespaces/sb-mock/queues/orders"
    }
  }

  mock_resource "azurerm_cosmosdb_account" {
    defaults = {
      endpoint = "https://cosmos-mock.documents.azure.com:443/"
      id       = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-mock"
    }
  }

  mock_resource "azurerm_cosmosdb_sql_container" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-mock/sqlDatabases/orders/containers/orders"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Web/serverFarms/plan-mock"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.OperationalInsights/workspaces/law-mock"
    }
  }

  mock_resource "azurerm_application_insights" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Insights/components/appi-mock"
    }
  }

  mock_resource "azurerm_monitor_private_link_scope" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Insights/privateLinkScopes/ampls-mock"
    }
  }

  mock_resource "azurerm_bastion_host" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/bastionHosts/bastion-mock"
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Insights/dataCollectionRules/dcr-mock"
    }
  }

  mock_resource "azurerm_monitor_data_collection_endpoint" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Insights/dataCollectionEndpoints/dce-mock"
    }
  }
}

mock_provider "azapi" {
  override_during = plan
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_string" {
    defaults = {
      result = "abc123"
    }
  }

  mock_resource "random_password" {
    defaults = {
      result = "mock-api-client-token"
    }
  }
}

override_resource {
  target = azurerm_subnet.bastion
  values = {
    id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/AzureBastionSubnet"
  }
}

run "secure_private_lab_plan" {
  command = plan

  variables {
    subscription_id           = "33333333-3333-3333-3333-333333333333"
    management_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIErIIoSy/5UFnc0+I3cG/Gcm3zeInwfhvvgT6K/FAY5F vnetlab-test"
  }

  assert {
    condition     = alltrue([for account in azurerm_storage_account.functions : account.shared_access_key_enabled == false])
    error_message = "Every Function storage account must reject Shared Key authorization."
  }

  assert {
    condition     = alltrue([for app in azurerm_function_app_flex_consumption.main : app.public_network_access_enabled == false])
    error_message = "Every Function App must have public network access disabled."
  }

  assert {
    condition     = azurerm_servicebus_namespace.main.local_auth_enabled == false
    error_message = "Service Bus local authentication must remain disabled."
  }

  assert {
    condition     = azurerm_cosmosdb_account.main.local_authentication_enabled == false
    error_message = "Cosmos DB local authentication must remain disabled."
  }
}
