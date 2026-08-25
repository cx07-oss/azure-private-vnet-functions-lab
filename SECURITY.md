# Security Policy

## Reporting a vulnerability

Please do not disclose suspected vulnerabilities, credentials, or deployment
details in a public issue. Use GitHub's private vulnerability reporting feature
under the repository's **Security** tab. If that feature is unavailable, contact
the maintainer through a private channel before sharing sensitive evidence.

## Sensitive local files

Never commit, force-add, attach to an issue, or upload to a public release any
of the following:

- Terraform state, variable files, backend configuration, or saved plans.
- Azure Functions `local.settings.json` files or `.env` files.
- SSH private keys, certificate bundles, password stores, or Azure CLI caches.
- Deployment packages, support-evidence folders, diagnostics, or deployment
  logs before a separate credential and personal-information review.

Terraform state for this lab contains generated secrets, including the API
client token. Treat all state and plan artifacts as credentials. If a secret is
exposed, revoke or rotate it immediately; deleting it from Git history is not a
substitute for rotation.

## Supported version

Security fixes are applied to the latest commit on `main`. This repository is a
learning lab and should be reviewed and adapted before production use.
