# CV project entry — AI engineering

## Recommended entry

**Secure Event-Driven Azure Platform for AI Workloads**

*Terraform, Python, Azure Functions, Service Bus, Cosmos DB, Managed Identity, Private Link, Key Vault, Azure Monitor, GitHub Actions, Azure DevOps*

- Engineered a private-by-default Azure platform for asynchronous API and AI-workload patterns, using two VNet-integrated Python Function Apps, Service Bus Premium, Cosmos DB, private DNS, and a Bastion-managed VM with no public IP.
- Eliminated cloud-service connection credentials by combining system- and user-assigned managed identities with least-privilege RBAC; disabled Storage Shared Key and local/key authentication across Storage, Service Bus, Cosmos DB, Key Vault, and Application Insights.
- Built and tested an event-driven producer/worker flow with queue-triggered processing, idempotent updates, Key Vault app-setting references, private deployment automation, and an end-to-end VNet smoke test.
- Implemented private observability through Log Analytics, workspace-based Application Insights, Azure Monitor Private Link, Azure Monitor Agent, a Data Collection Endpoint/DCR, and diagnostic settings across supported resources.
- Codified repeatable delivery with Terraform tests, Python unit/lint/indexing checks, GitHub Actions CI, and a security-separated Azure DevOps design using a non-sudo self-hosted deployment agent and workload-identity federation.

## One-line résumé version

Built a Terraform-managed Azure event-processing platform with private networking, passwordless managed-identity integrations, Python Functions, Service Bus, Cosmos DB, Key Vault, private observability, and secure CI/CD—the platform foundation commonly required for enterprise AI inference and agent workflows.

## Interview framing

This project demonstrates the production platform concerns around an AI system—identity, network isolation, asynchronous processing, secret management, observability, deployment, and failure handling—rather than claiming that a model was trained or evaluated. The producer/worker boundary can later wrap document ingestion, batch inference, evaluation, or agent jobs without redesigning the security plane.

Discuss these tradeoffs honestly:

- Flex Consumption was selected so Function host and deployment Storage could use managed identity while Shared Key remained disabled.
- A private endpoint controls network reachability but does not authenticate a caller, so the lab adds an API token and identifies Microsoft Entra App Service Authentication as the production evolution.
- The producer's Cosmos-write-plus-Service-Bus-send is a documented dual-write boundary; a production version would use a Cosmos change-feed outbox, stable idempotency keys, and reconciliation.
- Bastion Standard is the intentional public management ingress exception; all workload data planes and the VM are private.

## Foundry extension for a stronger AI portfolio signal

Your Azure AI Foundry account is useful for a later phase: add a model deployment, make the worker call it with managed identity, store prompts and inference metadata in Cosmos DB, and add an evaluation dataset plus latency/quality/cost telemetry. Only add model names, evaluation scores, or private-endpoint claims to the CV after that extension is deployed and measured.
