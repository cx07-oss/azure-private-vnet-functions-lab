.PHONY: fmt validate test package

fmt:
	terraform -chdir=terraform fmt -recursive
	python -m ruff format functions tests
	python -m ruff check --fix functions tests

validate:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate
	terraform -chdir=terraform test

test:
	python -m pytest

package:
	pwsh -File scripts/Package-Functions.ps1
