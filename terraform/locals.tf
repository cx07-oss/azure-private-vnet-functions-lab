resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  compact_prefix = replace(var.prefix, "-", "")
  stem           = "${var.prefix}-${var.environment}-${random_string.suffix.result}"

  names = {
    resource_group   = "rg-${local.stem}"
    vnet             = "vnet-${local.stem}"
    storage_producer = "stp${substr(local.compact_prefix, 0, 7)}${var.environment}${random_string.suffix.result}"
    storage_worker   = "stw${substr(local.compact_prefix, 0, 7)}${var.environment}${random_string.suffix.result}"
    key_vault        = "kv-${substr(local.compact_prefix, 0, 6)}-${var.environment}-${random_string.suffix.result}"
    service_bus      = substr("sb-${local.stem}", 0, 50)
    cosmos           = substr("cosmos-${local.stem}", 0, 44)
    producer         = substr("func-producer-${local.stem}", 0, 60)
    worker           = substr("func-worker-${local.stem}", 0, 60)
    vm               = "vm-mgmt-${local.stem}"
    law              = "law-${local.stem}"
    app_insights     = "appi-${local.stem}"
  }

  standard_tags = merge({
    environment = var.environment
    managed-by  = "terraform"
    project     = "private-vnet-functions-lab"
  }, var.tags)

  subnets = {
    functions = {
      address_prefix = "10.42.0.0/26"
    }
    management = {
      address_prefix = "10.42.1.0/24"
    }
    pe-functions = {
      address_prefix = "10.42.10.0/24"
    }
    pe-storage = {
      address_prefix = "10.42.11.0/24"
    }
    pe-servicebus = {
      address_prefix = "10.42.12.0/24"
    }
    pe-database = {
      address_prefix = "10.42.13.0/24"
    }
    pe-keyvault = {
      address_prefix = "10.42.14.0/24"
    }
    pe-monitor = {
      address_prefix = "10.42.15.0/24"
    }
  }

  private_dns_zones = {
    functions  = "privatelink.azurewebsites.net"
    blob       = "privatelink.blob.core.windows.net"
    queue      = "privatelink.queue.core.windows.net"
    table      = "privatelink.table.core.windows.net"
    servicebus = "privatelink.servicebus.windows.net"
    cosmos     = "privatelink.documents.azure.com"
    keyvault   = "privatelink.vaultcore.azure.net"
    monitor    = "privatelink.monitor.azure.com"
    oms        = "privatelink.oms.opinsights.azure.com"
    ods        = "privatelink.ods.opinsights.azure.com"
    agentsvc   = "privatelink.agentsvc.azure-automation.net"
  }

  deployment_containers = {
    producer = "deploy-producer"
    worker   = "deploy-worker"
  }

  cosmos_database_name  = "orders"
  cosmos_container_name = "orders"
  service_bus_queue     = "orders"
}
