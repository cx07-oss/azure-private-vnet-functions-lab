# Architecture and security design

## Network layout

| Subnet | CIDR | Purpose | Delegation / policy |
|---|---:|---|---|
| `snet-functions` | `10.42.0.0/26` | Outbound integration for both Flex apps | Delegated to `Microsoft.App/environments`; no endpoints |
| `snet-management` | `10.42.1.0/24` | Management VM private NIC | SSH only from Bastion; default outbound disabled; explicit NAT egress |
| `AzureBastionSubnet` | `10.42.2.0/26` | Bastion | Required exact name; dedicated |
| `snet-pe-functions` | `10.42.10.0/24` | Both Function inbound endpoints | NSG allows workload subnets on 443 |
| `snet-pe-storage` | `10.42.11.0/24` | Blob, Queue, and Table endpoints | NSG allows workload subnets on 443 |
| `snet-pe-servicebus` | `10.42.12.0/24` | Service Bus namespace endpoint | NSG allows 443 and AMQP 5671 |
| `snet-pe-database` | `10.42.13.0/24` | Cosmos DB SQL API endpoint | NSG allows 443 |
| `snet-pe-keyvault` | `10.42.14.0/24` | Key Vault endpoint | NSG allows 443 |
| `snet-pe-monitor` | `10.42.15.0/24` | Azure Monitor Private Link Scope | NSG allows 443 |

VNet integration is outbound and does not make a Function privately reachable. Each app also has an inbound `sites` private endpoint. Conversely, a private endpoint does not disable a public endpoint, so the Terraform resources explicitly set public network access to disabled.

Private-endpoint traffic bypasses App Service access-restriction evaluation. The endpoint subnet NSGs are therefore the source restriction. Function access restrictions are also set to deny by default as defense in depth for any future public-network configuration mistake.

## Private DNS

| Service / subresource | Zone |
|---|---|
| Function `sites` | `privatelink.azurewebsites.net` |
| Storage `blob` | `privatelink.blob.core.windows.net` |
| Storage `queue` | `privatelink.queue.core.windows.net` |
| Storage `table` | `privatelink.table.core.windows.net` |
| Service Bus `namespace` | `privatelink.servicebus.windows.net` |
| Cosmos DB `Sql` | `privatelink.documents.azure.com` |
| Key Vault `vault` | `privatelink.vaultcore.azure.net` |
| Azure Monitor `azuremonitor` | `privatelink.monitor.azure.com`, `privatelink.oms.opinsights.azure.com`, `privatelink.ods.opinsights.azure.com`, `privatelink.agentsvc.azure-automation.net`, and the Blob zone |

Clients always use the ordinary service hostname. Azure public DNS supplies the Private Link CNAME and the VNet-linked private zone supplies the RFC1918 address. Function zone groups also create the private SCM record required for deployments from the VM.

## Identity and RBAC matrix

| Principal | Scope | Role / permission | Reason |
|---|---|---|---|
| Producer UAMI | Producer Storage account | Storage Blob Data Owner | Functions host state and Flex deployment package |
| Producer UAMI | Producer Storage account | Storage Table Data Contributor | Host diagnostic events |
| Producer UAMI | Application Insights | Monitoring Metrics Publisher | Entra-authenticated telemetry ingestion |
| Producer system identity | Orders queue | Azure Service Bus Data Sender | Send only |
| Producer system identity | Orders Cosmos container | Cosmos DB Built-in Data Contributor | Data access constrained to one container |
| Producer system identity | Key Vault | Key Vault Secrets User | Resolve only app-setting secret references |
| Worker UAMI | Worker Storage account | Storage Blob Data Owner | Functions host state and Flex deployment package |
| Worker UAMI | Worker Storage account | Storage Table Data Contributor | Host diagnostic events |
| Worker UAMI | Application Insights | Monitoring Metrics Publisher | Entra-authenticated telemetry ingestion |
| Worker system identity | Orders queue | Azure Service Bus Data Receiver | Receive only |
| Worker system identity | Orders Cosmos container | Cosmos DB Built-in Data Contributor | Read/update constrained to one container |
| Worker system identity | Key Vault | Key Vault Secrets User | Resolve only app-setting secret references |
| Management VM system identity | Each Function App | Website Contributor | Deploy code through private SCM |
| Management VM system identity | Key Vault | Key Vault Secrets User | Retrieve the client token for tests |
| Management VM system identity | Lab resource group | Reader | Inspect resource state and diagnostic configuration without mutation |
| Management VM system identity | Log Analytics workspace | Log Analytics Reader | Run the documented private KQL troubleshooting queries |

The Flex deployment/host identities exist before the apps, avoiding the startup dependency between a new system identity and Storage RBAC. Flex currently resolves Key Vault app-setting references with the app's system identity; Terraform assigns the role after app creation and the deployment script requests a reference refresh.

Service Bus Receiver is intentionally narrower than Data Owner. Current Functions scaling can use a less-accurate peek fallback with Receiver-only access. A production custom role can add the documented namespace/queue management read action without granting send or ownership.

## Secret and connection management

Key Vault contains:

- `api-client-token`: a generated shared API token, referenced by both apps and retrieved by the management VM for the lab test.
- `cosmos-endpoint`: passwordless connection information, referenced by both apps.

Storage, Service Bus, Cosmos DB, and Application Insights local/key authentication are disabled. Their SDK/binding configuration uses normal endpoints plus managed identity; no Storage or Service Bus key is manufactured merely to put it in Key Vault.

Because Terraform creates the demo token, it exists in Terraform state. Use an encrypted, access-controlled remote backend in production and inject application secrets from a protected pipeline variable or external secret lifecycle rather than Terraform configuration.

## Reliability boundary

The producer deliberately demonstrates two service calls: create a Cosmos record, then publish a Service Bus message. Those operations are not an atomic transaction. A Service Bus failure after the Cosmos write can leave a `submitted` record without a queued message, and an HTTP retry creates a new order ID. That is acceptable for this infrastructure lab, but not a production order or inference workflow.

The production evolution is a transactional-outbox pattern: write the order and outbox event together, publish with a Cosmos change-feed processor, retain the stable client idempotency key, and reconcile unprocessed records. Service Bus duplicate detection and the worker's idempotent update are useful defenses, but they do not by themselves close the producer's dual-write gap.

## Availability, cost, and lab tradeoffs

- Service Bus Premium is required for Private Link and has a fixed capacity cost.
- Bastion Standard is used for tunneling/file transfer and has a fixed hourly cost.
- A NAT Gateway supplies explicit outbound-only connectivity for VM bootstrap, package updates, and deployment tooling; it adds a fixed hourly cost but no unsolicited inbound path.
- Cosmos DB serverless and Function Flex Consumption reduce idle workload cost.
- Both Functions share a `/26` integration subnet, which Microsoft recommends for multiple Flex apps. Production teams may separate apps further for scale and fault isolation.
- The header token is positive application authentication on top of private networking. For production user/client authentication, replace it with App Service Authentication using Microsoft Entra and an explicit API audience.
- Cosmos DB was selected instead of Azure SQL so data-plane access can be provisioned entirely through Azure RBAC. Azure SQL managed identity requires a separate contained-user/T-SQL bootstrap step from inside the VNet.
