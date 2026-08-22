provider "azurerm" {
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.AlertsManagement",
    "Microsoft.App",
    "Microsoft.Compute",
    "Microsoft.DocumentDB",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.ServiceBus",
    "Microsoft.Storage",
    "Microsoft.Web",
  ]

  features {
    # Storage is private and rejects Shared Key from creation. Terraform uses
    # ARM child resources for containers, so provider data-plane probing must
    # stay disabled during the external bootstrap apply.
    storage {
      data_plane_available = false
    }

    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azapi" {}

data "azurerm_client_config" "current" {}
