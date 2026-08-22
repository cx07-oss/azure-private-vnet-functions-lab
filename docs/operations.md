# Operations and troubleshooting

Run data-plane tests from the management VM. Portal and Cloud Shell sessions outside the VNet can still manage ARM resources but cannot reach the private data planes.

## Inspect Key Vault reference resolution

```bash
app_id="$(az functionapp show -g "$VNETLAB_RESOURCE_GROUP" -n "$VNETLAB_PRODUCER_APP" --query id -o tsv)"
az rest --method get \
  --uri "https://management.azure.com${app_id}/config/configreferences/appsettings?api-version=2024-11-01" |
  jq '.value[] | {setting: (.id | split("/") | last), status: .properties.status, details: .properties.details}'

az rest --method post \
  --uri "https://management.azure.com${app_id}/config/configreferences/appsettings/refresh?api-version=2022-03-01"
```

An unresolved reference usually means RBAC has not propagated, the system identity lacks `Key Vault Secrets User`, the vault hostname resolves publicly, or the Function cannot route to the vault private endpoint.

## Validate private DNS and ports

```bash
source /etc/profile.d/vnetlab.sh
nslookup "$VNETLAB_PRODUCER_APP.azurewebsites.net"
nslookup "$VNETLAB_PRODUCER_APP.scm.azurewebsites.net"
nslookup "$VNETLAB_KEY_VAULT.vault.azure.net"

curl -sv "https://$VNETLAB_PRODUCER_APP.azurewebsites.net/api/health"
```

The answer must be a `10.42.x.x` address. Do not configure applications with a `privatelink` hostname or a private IP; keep the normal service FQDN.

The health route confirms application settings and Key Vault reference resolution; it does not probe every dependency. Run `scripts/vm-smoke-test.sh` for an actual Function-to-Service Bus-to-Function-to-Cosmos readiness test.

## Inspect RBAC

```bash
producer_principal="$(az functionapp identity show \
  -g "$VNETLAB_RESOURCE_GROUP" -n "$VNETLAB_PRODUCER_APP" \
  --query principalId -o tsv)"
namespace="$(az servicebus namespace list -g "$VNETLAB_RESOURCE_GROUP" --query '[0].name' -o tsv)"
queue_id="$(az servicebus queue show -g "$VNETLAB_RESOURCE_GROUP" \
  --namespace-name "$namespace" -n orders --query id -o tsv)"
az role assignment list \
  --assignee-object-id "$producer_principal" \
  --scope "$queue_id" \
  --include-inherited \
  --fill-principal-name false \
  -o table
```

The query is intentionally scoped to the queue so the VM needs only resource-group Reader rather than subscription Reader. Repeat it with the Key Vault or Function resource ID to inspect another scope. RBAC changes commonly take several minutes; retry a new assignment after checking the exact principal, scope, and role.

## Service Bus and dead-letter queue

```bash
namespace="$(az servicebus namespace list -g "$VNETLAB_RESOURCE_GROUP" --query '[0].name' -o tsv)"
az servicebus queue show -g "$VNETLAB_RESOURCE_GROUP" \
  --namespace-name "$namespace" -n orders \
  --query '{active:countDetails.activeMessageCount,deadLetter:countDetails.deadLetterMessageCount}'
```

If active messages accumulate, check the worker's Service Bus Receiver assignment, `ServiceBusConnection__fullyQualifiedNamespace`, private DNS, and Function logs. Repeated application failures eventually move a message to the dead-letter queue after ten deliveries.

## Diagnostic settings and KQL

List a resource's supported categories and configured setting:

```bash
az monitor diagnostic-settings categories list --resource <resource-id> -o table
az monitor diagnostic-settings list --resource <resource-id> -o json
```

Run Log Analytics queries from the VM because query public access is disabled:

```bash
workspace_id="$(az monitor log-analytics workspace show \
  -g "$VNETLAB_RESOURCE_GROUP" --workspace-name <workspace-name> \
  --query customerId -o tsv)"

az monitor log-analytics query -w "$workspace_id" --analytics-query \
  'FunctionAppLogs | where TimeGenerated > ago(30m) | project TimeGenerated, FunctionName, Message | take 50' -o table

az monitor log-analytics query -w "$workspace_id" --analytics-query \
  'AzureDiagnostics | where TimeGenerated > ago(30m) | summarize count() by ResourceProvider, Category' -o table

az monitor log-analytics query -w "$workspace_id" --analytics-query \
  'Syslog | where TimeGenerated > ago(30m) | project TimeGenerated, HostName, Facility, SeverityLevel, SyslogMessage | take 50' -o table
```

Diagnostic ingestion is asynchronous. Wait several minutes after generating traffic before treating an empty query as a fault.

## Function deployment failures

- Deploy from the VM or another VNet-connected runner. Public SCM is disabled.
- Confirm both `<app>.azurewebsites.net` and `<app>.scm.azurewebsites.net` resolve privately.
- Confirm the deploying identity has `Website Contributor` on the specific app.
- Remote build needs outbound HTTPS to Python package sources. The integration subnet permits required Internet egress; the protected Azure services still accept only private data-plane traffic.
- Re-run `scripts/deploy-functions.sh`; it retries during RBAC and SCM propagation.
