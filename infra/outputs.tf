output "budget_id" {
  description = "Resource ID of the monthly subscription budget."
  value       = azurerm_consumption_budget_subscription.monthly.id
}

output "default_host_name" {
  description = "Auto-generated hostname of the Static Web App (*.azurestaticapps.net)."
  value       = azurerm_static_web_app.web.default_host_name
}

# The DNS records to create by hand at Hostpoint, in order.
# Show with: terraform output dns_records
#
# The provider marks validation_token as sensitive. It's wrapped in
# nonsensitive() because the token is published in public DNS anyway (that's
# its purpose) and it only proves domain ownership for this one app. Azure
# stops returning the token once the domain is validated; the placeholder
# text below is shown instead.
output "dns_records" {
  description = "DNS records to create at Hostpoint for the custom domains."
  value = [
    {
      step  = "1: domain ownership for ${var.apex_domain}"
      type  = "TXT"
      host  = "@"
      fqdn  = var.apex_domain
      value = nonsensitive(coalesce(azurerm_static_web_app_custom_domain.apex.validation_token, "(already validated; Azure no longer returns the token - leave the existing TXT record in place)"))
    },
    {
      step  = "2: point ${var.apex_domain} at the Static Web App"
      type  = "ANAME"
      host  = "@"
      fqdn  = var.apex_domain
      value = azurerm_static_web_app.web.default_host_name
    },
    {
      step  = "3: point www.${var.apex_domain} at the Static Web App (create BEFORE setting enable_www_domain = true)"
      type  = "CNAME"
      host  = "www"
      fqdn  = "www.${var.apex_domain}"
      value = azurerm_static_web_app.web.default_host_name
    },
  ]
}

# Deployment token used by GitHub Actions to upload the site.
# Never print it. Pipe it straight into the GitHub secret (needs approval):
#   terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN
output "deployment_token" {
  description = "Static Web App deployment token (API key). Sensitive."
  value       = azurerm_static_web_app.web.api_key
  sensitive   = true
}
