# Follow-up: Azure DevOps and a self-hosted deployment agent

This is intentionally phase 2. The first local Terraform apply creates the private VM and endpoints. The VM can then become the runner that reaches private Function SCM and all other private data planes.

## 1. Register the VM as an Azure Pipelines agent

In Azure DevOps:

1. Create an agent pool such as `vnetlab-private`.
2. Open **New agent**, select Linux x64, and copy the current package URL.
3. Create a short-lived PAT with only **Agent Pools: Read & manage**.

On the VM, set the values without writing the PAT to disk:

```bash
export ADO_ORG_URL='https://dev.azure.com/your-organization'
export ADO_POOL='vnetlab-private'
export ADO_AGENT_PACKAGE_URL='paste-the-current-linux-x64-package-url'
read -rsp 'Azure DevOps registration PAT: ' ADO_PAT && export ADO_PAT && echo

bash ./scripts/bootstrap-ado-agent.sh
unset ADO_PAT
```

The PAT is used only to register the agent. The script creates a dedicated `azdo` system account with no sudo rights, and the configured agent uses its own listener OAuth credential afterward. Revoke the PAT after registration.

## 2. Create and secure a remote Terraform backend

Use a separate lifecycle/resource group for Terraform state so destroying the lab cannot destroy its own state. Create a GPv2 account and private Blob container, enable versioning and soft delete, disable Shared Key, and assign the pipeline service principal `Storage Blob Data Contributor` on the state account.

Bootstrap can begin with a tightly restricted public network rule for the administrator. After the self-hosted agent is online, add a Blob private endpoint reachable from the management subnet/VNet, validate the agent can initialize, and disable public network access.

Copy and edit the backend examples on the administrator workstation:

```powershell
Copy-Item terraform/backend.tf.example terraform/backend.tf
Copy-Item terraform/backend.hcl.example backend.hcl
# Edit backend.hcl with the state account, container, and key.
```

Migrate the existing local state once, from a principal with access to both locations:

```powershell
terraform -chdir=terraform init `
  -migrate-state `
  -backend-config=../backend.hcl
```

Back up the local state before migration and verify `terraform state list` afterward. Never commit `.tfstate`, plan files, backend access keys, or PATs.

## 3. Azure DevOps permissions and protected files

- Create an Azure Resource Manager workload-identity-federated service connection for Terraform. Grant only the resource and role-assignment scopes the configuration needs.
- Upload `terraform.tfvars` and `backend.hcl` to **Pipelines > Library > Secure files**. Authorize only the protected deployment pipeline. The included deployment YAML downloads both to the job's temporary directory and Azure Pipelines deletes them after the job.
- Create an Azure DevOps Environment named `vnetlab-apply` and add a manual approval check.
- Keep the VM system identity for private code deployment. Terraform grants it Website Contributor on only the two apps, Key Vault Secrets User for the smoke-test token, resource-group Reader for diagnostics, and Log Analytics Reader on the lab workspace.
- Do not grant the CI pipeline identity access to the private agent pool, deployment service connection, Secure Files, variable groups, or deployment Environment. Disable pipeline setting **Allow scripts to access the OAuth token**.

## 4. Create the two included pipelines

Create a CI pipeline from `azure-pipelines.yml`. It runs pull-request validation on a disposable Microsoft-hosted runner and has no Azure credentials.

Create a second pipeline from `azure-pipelines.deploy.yml`. Disable implied YAML CI triggers if your Azure DevOps organization enables them, restrict queue permission to trusted operators, and require the protected `main` branch. Edit these deployment variables:

- `agentPool`
- `azureServiceConnection`
- `backendSecureFile` and `tfvarsSecureFile`
- the generated resource group, Function App, and Key Vault names

The deployment pipeline:

1. runs only when manually queued against protected `main`;
2. downloads the backend and variable files as short-lived Secure Files;
3. plans infrastructure with the federated service connection;
4. optionally regenerates and applies a plan after the Environment approval;
5. optionally deploys both code packages over private SCM using the VM identity;
6. optionally runs the end-to-end private smoke test.

Queue with `applyInfrastructure=false` for a trusted plan-only run. Set it to `true` only for an approved deployment. Pull requests never run on the management VM.

## Hardening follow-ups

- Replace the API header token with Microsoft Entra App Service Authentication and an explicit audience/allowed principal.
- For stronger workload separation, run the deployment agent on a second private VM with its own identity; Azure VM managed identity tokens are reachable by every local process that can access IMDS, so OS accounts alone do not create an identity boundary.
- Use an operator group and just-in-time Bastion access for interactive administration.
- Use separate subscriptions or resource groups for state, management, and workload planes.
- Add Defender for Cloud, Azure Policy assignments, workload identity federation, private DNS resolver/hub-spoke networking, and a tested backup/restore exercise.
- Use a custom Cosmos role that grants only producer-create and worker-read/replace data actions if the organization has validated those SDK metadata requirements.
