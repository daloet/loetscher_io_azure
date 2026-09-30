terraform {
  # Pinned to the installed Terraform minor release (1.16.x). "~> 1.16.0"
  # allows patch updates only, so a newer minor (with possible state format
  # or behavior changes) must be adopted deliberately.
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Patch updates only; bump the minor deliberately (Dependabot will propose it).
      version = "~> 4.81.0"
    }
  }
}

# The subscription ID is intentionally NOT set here or in any file.
# azurerm reads it from the ARM_SUBSCRIPTION_ID environment variable, e.g.:
#   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
# Authentication locally uses the Azure CLI login (`az login`); in CI it will use OIDC.
provider "azurerm" {
  features {}

  # Do not auto-register the ~20 default resource providers. Only the
  # providers we actually need are registered explicitly below.
  resource_provider_registrations = "none"

  # Register ONLY Microsoft.Web (needed for Static Web Apps), in addition to
  # the empty "none" set above. Registration is free.
  # NOTE: the provider does this when it starts up, i.e. on every
  # `terraform plan` and `terraform apply`, not only on apply. Once
  # Microsoft.Web is registered this is a no-op.
  resource_providers_to_register = ["Microsoft.Web"]
}
