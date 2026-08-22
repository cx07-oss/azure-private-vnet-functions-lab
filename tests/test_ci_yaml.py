from pathlib import Path

import pytest
import yaml


@pytest.mark.parametrize(
    "path",
    [
        Path("azure-pipelines.yml"),
        Path("azure-pipelines.deploy.yml"),
        Path(".github/workflows/ci.yml"),
    ],
)
def test_ci_yaml_is_well_formed(path: Path) -> None:
    document = yaml.safe_load(path.read_text(encoding="utf-8"))

    assert isinstance(document, dict)
