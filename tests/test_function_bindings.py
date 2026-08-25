from __future__ import annotations

import importlib.util
import inspect
import sys
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[1]


def load_function_app(project: str):
    module_path = ROOT / "functions" / project / "function_app.py"
    spec = importlib.util.spec_from_file_location(f"{project}_function_app", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("project", ["producer", "worker"])
def test_binding_names_match_handler_parameters(project: str) -> None:
    module = load_function_app(project)

    for function in module.app.get_functions():
        binding_names = {
            binding["name"]
            for binding in function.get_bindings_dict()["bindings"]
            if binding["name"] != "$return"
        }
        parameter_names = set(inspect.signature(function.get_user_function()).parameters)
        assert parameter_names == binding_names, (
            f"{project}.{function.get_function_name()} declares bindings "
            f"{sorted(binding_names)!r}, but its handler parameters are "
            f"{sorted(parameter_names)!r}"
        )


def test_worker_app_does_not_collide_with_functions_worker(monkeypatch) -> None:
    monkeypatch.setitem(sys.modules, "worker", ModuleType("worker"))

    module = load_function_app("worker")

    assert {function.get_function_name() for function in module.app.get_functions()} == {
        "get_order",
        "health",
        "process_order",
    }
