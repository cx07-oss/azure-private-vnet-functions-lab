#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_group="${VNETLAB_RESOURCE_GROUP:?Set VNETLAB_RESOURCE_GROUP or source /etc/profile.d/vnetlab.sh}"
producer_app="${VNETLAB_PRODUCER_APP:?Set VNETLAB_PRODUCER_APP or source /etc/profile.d/vnetlab.sh}"
worker_app="${VNETLAB_WORKER_APP:?Set VNETLAB_WORKER_APP or source /etc/profile.d/vnetlab.sh}"
dist_dir="${repository_root}/dist"
retry_attempts="${VNETLAB_DEPLOY_RETRY_ATTEMPTS:-30}"
retry_delay_seconds="${VNETLAB_DEPLOY_RETRY_DELAY_SECONDS:-10}"

if ! az account show >/dev/null 2>&1; then
  az login --identity --output none
fi

mkdir -p "${dist_dir}"

package_app() {
  local app="$1"
  local source_dir="${repository_root}/functions/${app}"
  local package="${dist_dir}/${app}.zip"

  rm -f -- "${package}"
  (
    cd "${source_dir}"
    zip -qr "${package}" . \
      -x 'local.settings.json' 'local.settings.json.example' \
      -x '*/__pycache__/*' '*.pyc' '.python_packages/*'
  )
  printf 'Packaged %s\n' "${package}"
}

wait_for_key_vault_references() {
  local app_name="$1"
  local subscription_id app_id references reference_count unresolved_count
  subscription_id="$(az account show --query id --output tsv)"
  app_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}"

  for attempt in $(seq 1 "${retry_attempts}"); do
    if az rest \
      --method post \
      --uri "https://management.azure.com${app_id}/config/configreferences/appsettings/refresh?api-version=2022-03-01" \
      --output none 2>/dev/null && \
      references="$(az rest \
        --method get \
        --uri "https://management.azure.com${app_id}/config/configreferences/appsettings?api-version=2024-11-01" \
        --output json 2>/dev/null)"; then
      reference_count="$(jq '[.value[]?] | length' <<<"${references}")"
      unresolved_count="$(jq '[.value[]? | select(.properties.status != "Resolved")] | length' <<<"${references}")"
      if [[ "${reference_count}" -ge 2 && "${unresolved_count}" -eq 0 ]]; then
        printf 'Key Vault references resolved for %s\n' "${app_name}"
        return 0
      fi
    fi

    printf 'Key Vault references for %s are not ready (attempt %s/%s).\n' \
      "${app_name}" "${attempt}" "${retry_attempts}" >&2
    sleep "${retry_delay_seconds}"
  done

  if [[ -n "${references:-}" ]]; then
    jq -r '.value[]? | [(.id | split("/") | last), (.properties.status // "Unknown"), (.properties.details // "")] | @tsv' \
      <<<"${references}" >&2
  fi
  printf 'Key Vault references did not resolve for %s.\n' "${app_name}" >&2
  return 1
}

deploy_app() {
  local app_name="$1"
  local package="$2"

  for attempt in $(seq 1 "${retry_attempts}"); do
    if az functionapp deployment source config-zip \
      --resource-group "${resource_group}" \
      --name "${app_name}" \
      --src "${package}" \
      --build-remote true \
      --output none; then
      printf 'Deployed %s\n' "${app_name}"
      return 0
    fi
    printf 'Deployment attempt %s/%s failed; waiting for RBAC/SCM propagation...\n' \
      "${attempt}" "${retry_attempts}" >&2
    sleep "${retry_delay_seconds}"
  done

  printf 'Deployment failed after %s attempts: %s\n' "${retry_attempts}" "${app_name}" >&2
  return 1
}

remove_injected_deployment_connection_string() {
  local app_name="$1"

  # AzureRM can inject a key-based deployment setting with an empty AccountKey
  # even when Flex deployment storage is configured for managed identity. If
  # present, the host can select the broken key path instead of the UAMI path.
  az functionapp config appsettings delete \
    --resource-group "${resource_group}" \
    --name "${app_name}" \
    --setting-names DEPLOYMENT_STORAGE_CONNECTION_STRING \
    --output none
}

package_app producer
package_app worker

remove_injected_deployment_connection_string "${producer_app}"
remove_injected_deployment_connection_string "${worker_app}"
wait_for_key_vault_references "${producer_app}"
wait_for_key_vault_references "${worker_app}"
deploy_app "${producer_app}" "${dist_dir}/producer.zip"
deploy_app "${worker_app}" "${dist_dir}/worker.zip"

printf 'Both Function Apps are deployed. Run scripts/vm-smoke-test.sh next.\n'
