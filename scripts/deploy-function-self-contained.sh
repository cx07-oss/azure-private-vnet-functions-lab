#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/deploy-function-self-contained.sh [producer|worker]

Builds one Function App as a self-contained Linux package, including
.python_packages at the ZIP root, validates decorator discovery from that exact
staging tree, and deploys it through OneDeploy with remote build disabled.

Environment overrides:
  VNETLAB_BUILD_PYTHON                 Python executable matching the live app runtime (default: python3)
  VNETLAB_DEPLOY_RETRY_ATTEMPTS       Index/health attempts (default: 30)
  VNETLAB_DEPLOY_RETRY_DELAY_SECONDS  Delay between attempts (default: 10)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

target="${1:-producer}"
case "${target}" in
  producer)
    app_env_name="VNETLAB_PRODUCER_APP"
    expected_functions="health,create_order"
    ;;
  worker)
    app_env_name="VNETLAB_WORKER_APP"
    expected_functions="process_order,health,get_order"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ -f /etc/profile.d/vnetlab.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/vnetlab.sh
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_group="${VNETLAB_RESOURCE_GROUP:?Set VNETLAB_RESOURCE_GROUP or source /etc/profile.d/vnetlab.sh}"
app_name="${!app_env_name:?Set ${app_env_name} or source /etc/profile.d/vnetlab.sh}"
build_python="${VNETLAB_BUILD_PYTHON:-python3}"
retry_attempts="${VNETLAB_DEPLOY_RETRY_ATTEMPTS:-30}"
retry_delay_seconds="${VNETLAB_DEPLOY_RETRY_DELAY_SECONDS:-10}"
source_dir="${repository_root}/functions/${target}"
dist_dir="${repository_root}/dist/self-contained"

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'Self-contained Function packages must be built on Linux.\n' >&2
  exit 1
fi

for command in az curl jq sha256sum unzip zip "${build_python}"; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "${command}" >&2
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  az login --identity --output none
fi

subscription_id="$(az account show --query id --output tsv)"
app_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}"
runtime_json="$(az rest \
  --method get \
  --uri "https://management.azure.com${app_id}?api-version=2024-04-01" \
  --query properties.functionAppConfig.runtime \
  --output json)"
runtime_name="$(jq --raw-output '.name // empty' <<<"${runtime_json}")"
runtime_version="$(jq --raw-output '.version // empty' <<<"${runtime_json}")"
build_python_version="$("${build_python}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

if [[ "${runtime_name}" != "python" || -z "${runtime_version}" ]]; then
  printf 'Could not confirm a Python Flex runtime for %s: %s\n' "${app_name}" "${runtime_json}" >&2
  exit 1
fi

if [[ "${build_python_version}" != "${runtime_version}" ]]; then
  cat >&2 <<EOF
Build/runtime mismatch: ${build_python} is Python ${build_python_version}, but
${app_name} runs Python ${runtime_version}. Support requested an exact minor-version
match. Set VNETLAB_BUILD_PYTHON to a Linux Python ${runtime_version} executable,
or change the Function runtime and apply Terraform before running this test.
EOF
  exit 1
fi

if ! "${build_python}" -m pip --version >/dev/null 2>&1; then
  printf '%s does not have pip. Select a Python %s virtual environment seeded with pip.\n' \
    "${build_python}" "${runtime_version}" >&2
  exit 1
fi

mkdir -p "${dist_dir}"
stage_root="$(mktemp -d "/tmp/vnetlab-${target}-self-contained.XXXXXX")"
stage_app="${stage_root}/app"
package="${dist_dir}/${target}-self-contained-py${runtime_version}.zip"
pip_log="${dist_dir}/${target}-self-contained-pip-install.log"
pip_report="${dist_dir}/${target}-self-contained-pip-report.json"
top_level_report="${dist_dir}/${target}-self-contained-top-level.txt"

cleanup() {
  rm -rf -- "${stage_root}"
}
trap cleanup EXIT

mkdir -p "${stage_app}/.python_packages/lib/site-packages"
cp -- "${source_dir}/function_app.py" "${stage_app}/"
cp -- "${source_dir}/host.json" "${stage_app}/"
cp -- "${source_dir}/requirements.txt" "${stage_app}/"
cp -R -- "${source_dir}/${target}" "${stage_app}/${target}"
find "${stage_app}" -type d -name __pycache__ -prune -exec rm -rf -- {} +
find "${stage_app}" -type f -name '*.pyc' -delete

printf 'Installing Python %s dependencies into the staged package...\n' "${runtime_version}"
"${build_python}" -m pip install \
  --disable-pip-version-check \
  --no-compile \
  --requirement "${stage_app}/requirements.txt" \
  --target "${stage_app}/.python_packages/lib/site-packages" \
  --report "${pip_report}" 2>&1 | tee "${pip_log}"

printf 'Validating imports and decorator discovery from the staged package...\n'
(
  cd "${stage_app}"
  EXPECTED_FUNCTIONS="${expected_functions}" \
  PYTHONPATH="${stage_app}/.python_packages/lib/site-packages" \
    "${build_python}" - <<'PY'
import os

import function_app

expected = set(os.environ["EXPECTED_FUNCTIONS"].split(","))
actual = {function.get_function_name() for function in function_app.app.get_functions()}
print(f"Indexed functions: {sorted(actual)}")
if actual != expected:
    raise SystemExit(f"Function discovery mismatch: expected {sorted(expected)}, got {sorted(actual)}")
PY
)

# The discovery import creates bytecode caches. Remove them after validation so
# the support artifact contains only source and runtime dependencies.
find "${stage_app}" -type d -name __pycache__ -prune -exec rm -rf -- {} +
find "${stage_app}" -type f -name '*.pyc' -delete

rm -f -- "${package}"
(
  cd "${stage_app}"
  zip -qr "${package}" . -x '*/__pycache__/*' '*.pyc'
)

unzip -Z1 "${package}" | sed 's#/.*##' | sort -u >"${top_level_report}"
for required in function_app.py host.json requirements.txt "${target}" .python_packages; do
  if ! grep -Fxq "${required}" "${top_level_report}"; then
    printf 'Package is missing required top-level entry: %s\n' "${required}" >&2
    exit 1
  fi
done

printf 'Self-contained package top level:\n'
cat "${top_level_report}"
sha256sum "${package}"

# AzureRM can inject a key-based deployment setting with an empty AccountKey
# even though Flex deployment storage uses managed identity. Remove it before
# testing the self-contained package so the broken key path cannot be selected.
az functionapp config appsettings delete \
  --resource-group "${resource_group}" \
  --name "${app_name}" \
  --setting-names DEPLOYMENT_STORAGE_CONNECTION_STRING \
  --output none

printf 'Deploying %s with OneDeploy remote build disabled...\n' "${app_name}"
az functionapp deployment source config-zip \
  --resource-group "${resource_group}" \
  --name "${app_name}" \
  --src "${package}" \
  --build-remote false \
  --output none

printf 'Waiting for Azure to index the expected functions...\n'
for attempt in $(seq 1 "${retry_attempts}"); do
  functions_json="$(az functionapp function list \
    --resource-group "${resource_group}" \
    --name "${app_name}" \
    --output json 2>/dev/null || printf '[]')"
  indexed_count="$(jq 'length' <<<"${functions_json}")"
  if [[ "${indexed_count}" -ge "$(tr ',' '\n' <<<"${expected_functions}" | wc -l)" ]]; then
    jq --raw-output '.[].name' <<<"${functions_json}"
    printf 'Function indexing succeeded for %s.\n' "${app_name}"
    health_response_file="${stage_root}/health-response.txt"
    if ! health_status="$(curl --silent --show-error --max-time 30 \
      --output "${health_response_file}" \
      --write-out '%{http_code}' \
      "https://${app_name}.azurewebsites.net/api/health")"; then
      printf 'Functions were indexed, but the private health route could not be reached.\n' >&2
      exit 1
    fi

    if [[ -s "${health_response_file}" ]] && jq -e . "${health_response_file}" >/dev/null 2>&1; then
      jq . "${health_response_file}"
    elif [[ -s "${health_response_file}" ]]; then
      cat "${health_response_file}"
      printf '\n'
    fi

    if [[ "${health_status}" == "404" ]]; then
      printf 'Functions were indexed, but /api/health still returned HTTP 404.\n' >&2
      exit 1
    elif [[ "${health_status}" == "200" ]]; then
      printf 'The private health route returned HTTP 200.\n'
    else
      printf 'The route is indexed and returned HTTP %s (not 404), but the app is not fully healthy yet.\n' "${health_status}"
    fi

    printf 'Self-contained deployment validation completed.\n'
    exit 0
  fi
  printf 'Functions are not indexed yet (attempt %s/%s).\n' \
    "${attempt}" "${retry_attempts}" >&2
  sleep "${retry_delay_seconds}"
done

cat >&2 <<EOF
The self-contained deployment completed, but Azure did not index the expected
functions. Preserve these support artifacts:
  ${package}
  ${pip_log}
  ${pip_report}
  ${top_level_report}

Rollback to the previous remote-build workflow with:
  cd ${repository_root}
  bash scripts/deploy-functions.sh
EOF
exit 1
