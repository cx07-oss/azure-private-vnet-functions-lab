variable "name" {
  description = "Diagnostic setting name."
  type        = string
}
variable "target_resource_id" {
  description = "Resource ID that exposes Azure Monitor diagnostic categories."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Destination Log Analytics workspace resource ID."
  type        = string
}
