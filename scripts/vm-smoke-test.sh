#!/usr/bin/env bash
set -euo pipefail

resource_group="${VNETLAB_RESOURCE_GROUP:?Set VNETLAB_RESOURCE_GROUP or source /etc/profile.d/vnetlab.sh}"
producer_app="${VNETLAB_PRODUCER_APP:?Set VNETLAB_PRODUCER_APP or source /etc/profile.d/vnetlab.sh}"
worker_app="${VNETLAB_WORKER_APP:?Set VNETLAB_WORKER_APP or source /etc/profile.d/vnetlab.sh}"
key_vault="${VNETLAB_KEY_VAULT:?Set VNETLAB_KEY_VAULT or source /etc/profile.d/vnetlab.sh}"
retry_attempts="${VNETLAB_SMOKE_RETRY_ATTEMPTS:-30}"
retry_delay_seconds="${VNETLAB_SMOKE_RETRY_DELAY_SECONDS:-10}"

if ! az account show >/dev/null 2>&1; then
  az login --identity --output none
fi

api_token=""
for attempt in $(seq 1 "${retry_attempts}"); do
  if candidate="$(az keyvault secret show \
    --vault-name "${key_vault}" \
    --name api-client-token \
    --query value \
    --output tsv 2>/dev/null)" && [[ -n "${candidate}" ]]; then
    api_token="${candidate}"
    break
  fi
  printf 'Key Vault access is not ready (attempt %s/%s).\n' \
    "${attempt}" "${retry_attempts}" >&2
  sleep "${retry_delay_seconds}"
done
if [[ -z "${api_token}" ]]; then
  printf 'Could not retrieve the smoke-test token from Key Vault.\n' >&2
  exit 1
fi

producer_host="${producer_app}.azurewebsites.net"
worker_host="${worker_app}.azurewebsites.net"

printf 'Private DNS checks (addresses should be in 10.42.0.0/16):\n'
nslookup "${producer_host}"
nslookup "${worker_host}"

wait_for_config_health() {
  local host="$1"
  local body
  for attempt in $(seq 1 "${retry_attempts}"); do
    if body="$(curl --fail --silent --show-error "https://${host}/api/health" 2>/dev/null)" && \
      jq -e '.status == "ok"' >/dev/null 2>&1 <<<"${body}"; then
      printf '%s\n' "${body}" | jq .
      return 0
    fi
    printf 'Configuration health for %s is not ready (attempt %s/%s).\n' \
      "${host}" "${attempt}" "${retry_attempts}" >&2
    sleep "${retry_delay_seconds}"
  done
  printf 'Configuration health did not become ready for %s.\n' "${host}" >&2
  return 1
}

printf 'Function configuration-health checks:\n'
wait_for_config_health "${producer_host}"
wait_for_config_health "${worker_host}"

response="$(curl --fail --silent --show-error \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "X-VNetLab-Token: ${api_token}" \
  --data '{"customerId":"bastion-vm","amount":"42.50","description":"private VNet smoke test"}' \
  "https://${producer_host}/api/orders")"

printf '%s\n' "${response}" | jq .
order_id="$(printf '%s' "${response}" | jq --raw-output '.orderId')"
if [[ -z "${order_id}" || "${order_id}" == "null" ]]; then
  printf 'Producer response did not contain an orderId.\n' >&2
  exit 1
fi

status_url="https://${worker_host}/api/orders/${order_id}"
status_body="$(mktemp /tmp/vnetlab-status.XXXXXX)"
trap 'rm -f -- "${status_body}"' EXIT
for attempt in $(seq 1 "${retry_attempts}"); do
  http_code=""
  if http_code="$(curl --silent --show-error \
    --output "${status_body}" \
    --write-out '%{http_code}' \
    --header "X-VNetLab-Token: ${api_token}" \
    "${status_url}")"; then
    if [[ "${http_code}" == "200" ]] && jq -e . "${status_body}" >/dev/null 2>&1; then
      status="$(jq --raw-output '.status // "unknown"' "${status_body}")"
      printf 'Attempt %s: order %s is %s\n' "${attempt}" "${order_id}" "${status}"
      if [[ "${status}" == "processed" ]]; then
        jq . "${status_body}"
        printf 'End-to-end private Function -> Service Bus -> Function -> Cosmos flow succeeded.\n'
        exit 0
      fi
    else
      printf 'Attempt %s: worker returned HTTP %s; retrying.\n' "${attempt}" "${http_code}" >&2
    fi
  else
    printf 'Attempt %s: worker request failed; retrying.\n' "${attempt}" >&2
  fi
  sleep "${retry_delay_seconds}"
done

printf 'Order did not reach processed state within the retry window. Check Service Bus dead-letter and Function logs.\n' >&2
exit 1
