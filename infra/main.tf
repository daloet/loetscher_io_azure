# Website infrastructure: resource group, Static Web App (Free) and custom domains.
# The subscription budget lives in budget.tf.
# DNS records are NOT managed here; they are created by hand at Hostpoint.
# `terraform output dns_records` lists exactly what to create.

resource "azurerm_resource_group" "web" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_static_web_app" "web" {
  name                = var.static_web_app_name
  resource_group_name = azurerm_resource_group.web.name
  location            = var.static_web_app_location # differs from the RG on purpose, see variables.tf

  # Free tier: no charges. Overage billing doesn't exist on Free, so traffic
  # above the quota can't be billed. Never change this to "Standard" without
  # checking the cost first.
  sku_tier = "Free"
  sku_size = "Free"

  # Apply staticwebapp.config.json on deploy. We rely on it for the security
  # headers (CSP, HSTS, ...), so this must stay true.
  configuration_file_changes_enabled = true

  # Pull requests get their own temporary preview URL (Free allows 3 at a time).
  preview_environments_enabled = true

  # This is a public website. "false" only makes sense together with a
  # private endpoint, which Free doesn't support.
  public_network_access_enabled = true

  # Deliberately no app_settings (no backend), no identity and no basic_auth
  # (both are unavailable on Free). The site is deployed by GitHub Actions
  # using the deployment token (output "deployment_token"), so no repository
  # settings are needed here.

  tags = var.tags
}

# Apex domain (loetscher.io), validated with a TXT record.
# Creating this resource does NOT wait for DNS validation: Azure generates a
# token, Terraform stores it and finishes. Azure then keeps checking DNS in
# the background until the TXT record (see output "dns_records") appears.
resource "azurerm_static_web_app_custom_domain" "apex" {
  static_web_app_id = azurerm_static_web_app.web.id
  domain_name       = var.apex_domain
  validation_type   = "dns-txt-token"
}

# www subdomain, validated by its CNAME record pointing at the SWA hostname.
# Unlike TXT validation, Azure checks the CNAME IMMEDIATELY and Terraform waits
# for the result, so the apply FAILS if the CNAME doesn't exist yet.
# Hence the two-step rollout:
#   1. apply with enable_www_domain = false -> creates the resource group, the
#      SWA and the apex domain (which returns the TXT token).
#   2. Create the DNS records at Hostpoint (terraform output dns_records).
#   3. Set enable_www_domain = true in terraform.tfvars and apply again.
# The redirect from www to the apex is configured separately (Step 5).
resource "azurerm_static_web_app_custom_domain" "www" {
  count = var.enable_www_domain ? 1 : 0

  static_web_app_id = azurerm_static_web_app.web.id
  domain_name       = "www.${var.apex_domain}"
  validation_type   = "cname-delegation"
}
