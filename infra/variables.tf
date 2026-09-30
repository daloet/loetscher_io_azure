variable "budget_alert_email" {
  description = "Email address that receives subscription budget alerts."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a valid email address."
  }
}

variable "budget_amount" {
  description = "Monthly subscription budget amount in the billing currency."
  type        = number
  default     = 5

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be greater than 0."
  }
}

variable "location" {
  description = "Azure region for the resource group (metadata only)."
  type        = string
  default     = "westeurope"
}

variable "static_web_app_location" {
  description = "Azure region for the Static Web App metadata. Content is served from Azure's global edge regardless of this value."
  type        = string
  # westeurope rejected new Static Web Apps for this subscription
  # ("region is currently not accepting new customers"), so eastus2 is used.
  default = "eastus2"

  validation {
    # Regions where Microsoft.Web/staticSites can be created.
    condition     = contains(["westeurope", "centralus", "eastus2", "westus2", "eastasia"], var.static_web_app_location)
    error_message = "static_web_app_location must be a region that supports Static Web Apps: westeurope, centralus, eastus2, westus2 or eastasia."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group that holds the website resources."
  type        = string
  default     = "rg-loetscher-web"
}

variable "static_web_app_name" {
  description = "Name of the Azure Static Web App."
  type        = string
  default     = "swa-loetscher-web"
}

variable "apex_domain" {
  description = "Apex (root) custom domain of the website, e.g. loetscher.io. This is the canonical host."
  type        = string
  default     = "loetscher.io"
}

variable "enable_www_domain" {
  description = "Add www.<apex_domain> as a custom domain. Set to true ONLY after the www CNAME exists at the DNS provider (see main.tf)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default = {
    project    = "loetscher.io"
    managed_by = "terraform"
  }
}
