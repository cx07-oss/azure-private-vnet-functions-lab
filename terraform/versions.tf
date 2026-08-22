terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.81 is the final v4 line. Keep this lab off the newly released v5
      # until its breaking changes are deliberately adopted.
      version = "~> 4.81.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
