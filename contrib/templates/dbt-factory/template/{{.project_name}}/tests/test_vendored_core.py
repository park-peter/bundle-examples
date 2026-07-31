"""Pins the vendored databricks_dbt_factory version, so a wrong-version vendor fails CI."""

from databricks_dbt_factory.__about__ import __version__


def test_vendored_core_is_pinned_version():
    assert __version__ == "0.3.2"
