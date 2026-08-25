variable "subscription_id" {
  description = "Azure subscription ID. May be omitted when ARM_SUBSCRIPTION_ID is set."
  type        = string
  default     = null
  nullable    = true
}

variable "prefix" {
  description = "Short lowercase prefix used in resource names."
  type        = string
  default     = "vnetlab"

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]{1,10}[a-z0-9]$", var.prefix)) &&
      !strcontains(var.prefix, "--")
    )
    error_message = "prefix must be 3-12 lowercase letters or digits, may contain single internal hyphens, and must start with a letter."
  }
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.environment))
    error_message = "environment must be 2-6 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region. It must support Functions Flex Consumption."
  type        = string
  default     = "australiaeast"
}

variable "cosmos_location" {
  description = "Optional Azure region for Cosmos DB. When null, Cosmos DB uses the main workload region."
  type        = string
  default     = null
  nullable    = true
}

variable "management_vm_size" {
  description = "Size of the private management VM."
  type        = string
  default     = "Standard_B2s"
}

variable "management_admin_username" {
  description = "Local administrator name for the management VM."
  type        = string
  default     = "azureadmin"
}

variable "management_ssh_public_key" {
  description = "OpenSSH public key used to connect to the management VM through Bastion."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519|ecdsa-[^ ]+) [A-Za-z0-9+/=]+", trimspace(var.management_ssh_public_key)))
    error_message = "management_ssh_public_key must be a valid OpenSSH public key."
  }
}

variable "function_maximum_instance_count" {
  description = "Maximum scale-out count for each Flex Consumption app."
  type        = number
  default     = 20

  validation {
    condition     = var.function_maximum_instance_count >= 2 && var.function_maximum_instance_count <= 1000
    error_message = "function_maximum_instance_count must be between 2 and 1000."
  }
}

variable "function_instance_memory_mb" {
  description = "Memory per Flex Consumption instance."
  type        = number
  default     = 2048

  validation {
    condition     = contains([512, 2048, 4096], var.function_instance_memory_mb)
    error_message = "function_instance_memory_mb must be 512, 2048, or 4096."
  }
}

variable "function_runtime_version" {
  description = "Python runtime version for both Flex Consumption Function Apps."
  type        = string
  default     = "3.12"

  validation {
    condition     = contains(["3.11", "3.12", "3.13", "3.14"], var.function_runtime_version)
    error_message = "function_runtime_version must be a Python version supported by Flex Consumption."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention period."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "enable_subscription_activity_diagnostics" {
  description = "Export the subscription Activity Log to this lab workspace. Requires subscription-scope diagnosticSettings/write permission."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge with the standard lab tags."
  type        = map(string)
  default     = {}
}
