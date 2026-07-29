"""
Smoke test for the vendored databricks_dbt_factory core. Runs with no dbt manifest, so it always
executes (unlike the manifest-gated glue tests) and catches a broken or wrong-version vendor.
"""

from databricks_dbt_factory.__about__ import __version__
from databricks_dbt_factory.DbtFactory import DbtFactory
from databricks_dbt_factory.DbtTask import DbtTaskOptions, TaskType
from databricks_dbt_factory.TaskFactory import DbtDependencyResolver, ModelTaskFactory


def test_vendored_core_is_pinned_version():
    assert __version__ == "0.3.1"


def test_factory_generates_notebook_tasks():
    resolver = DbtDependencyResolver()
    options = DbtTaskOptions(
        environment_key="Default",
        notebook_path="./nb.py",
        task_type=TaskType.NOTEBOOK,
    )
    factory = DbtFactory({"model": ModelTaskFactory(resolver, options, "--target dev")})

    node = {
        "resource_type": "model",
        "name": "orders",
        "package_name": "shop",
        "fqn": ["shop", "orders"],
    }
    tasks = factory.create_tasks({"nodes": {"model.shop.orders": node}})

    assert [task["task_key"] for task in tasks] == ["orders_model"]
    assert "notebook_task" in tasks[0]
