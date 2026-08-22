#!/usr/bin/env bash
set -euo pipefail

: "${ADO_ORG_URL:?Set ADO_ORG_URL}"
: "${ADO_POOL:?Set ADO_POOL}"
: "${ADO_AGENT_PACKAGE_URL:?Set ADO_AGENT_PACKAGE_URL from the Azure DevOps New agent page}"
: "${ADO_PAT:?Set ADO_PAT to a short-lived Agent Pools registration PAT}"

terraform_version="${TERRAFORM_VERSION:-1.15.8}"
agent_name="${ADO_AGENT_NAME:-$(hostname)}"
agent_user="${ADO_AGENT_USER:-azdo}"
agent_root="/opt/azdo-agent"
work_root="/opt/azdo-work"

if [[ ! "${agent_user}" =~ ^[a-z_][a-z0-9_-]*$ || "${agent_user}" == "root" ]]; then
  printf 'ADO_AGENT_USER must be a non-root local account name.\n' >&2
  exit 1
fi

install_terraform() {
  local archive="/tmp/terraform_${terraform_version}_linux_amd64.zip"
  local checksums="/tmp/terraform_${terraform_version}_SHA256SUMS"

  curl --fail --location --silent --show-error \
    "https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip" \
    --output "${archive}"
  curl --fail --location --silent --show-error \
    "https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_SHA256SUMS" \
    --output "${checksums}"
  (
    cd /tmp
    grep "terraform_${terraform_version}_linux_amd64.zip" "${checksums}" | sha256sum --check --strict
  )
  sudo unzip -o "${archive}" -d /usr/local/bin
  sudo chmod 0755 /usr/local/bin/terraform
}

if ! command -v terraform >/dev/null 2>&1; then
  install_terraform
fi

if ! id "${agent_user}" >/dev/null 2>&1; then
  sudo useradd --system --create-home --shell /bin/bash "${agent_user}"
fi
agent_group="$(id -gn "${agent_user}")"
sudo install -d -o "${agent_user}" -g "${agent_group}" -m 0750 "${agent_root}" "${work_root}"
agent_archive="$(mktemp --suffix=.tar.gz /tmp/azdo-agent.XXXXXX)"
trap 'rm -f -- "${agent_archive}"' EXIT

curl --fail --location --silent --show-error "${ADO_AGENT_PACKAGE_URL}" --output "${agent_archive}"
sudo tar -xzf "${agent_archive}" -C "${agent_root}"
sudo chown -R "${agent_user}:${agent_group}" "${agent_root}" "${work_root}"

sudo --user="${agent_user}" --set-home --chdir="${agent_root}" ./config.sh \
  --unattended \
  --acceptTeeEula \
  --url "${ADO_ORG_URL}" \
  --auth pat \
  --token "${ADO_PAT}" \
  --pool "${ADO_POOL}" \
  --agent "${agent_name}" \
  --work "${work_root}" \
  --replace

unset ADO_PAT
sudo --chdir="${agent_root}" ./svc.sh install "${agent_user}"
sudo --chdir="${agent_root}" ./svc.sh start
sudo --chdir="${agent_root}" ./svc.sh status

printf 'Agent %s registered in pool %s as non-sudo user %s. Revoke the registration PAT now.\n' \
  "${agent_name}" "${ADO_POOL}" "${agent_user}"
