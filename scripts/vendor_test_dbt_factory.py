"""
Adapt upstream's tests/test_dbt_factory.py for the vendored bundle: drop the golden-spec tests and
the run_job_spec_test helper (they import job_spec, a CLI file the bundle does not vendor) and the
imports used only by them, keeping the DAG/gating tests that exercise only the vendored core.

Usage: vendor_test_dbt_factory.py <upstream_test_dbt_factory.py> <output_path>
"""

import re
import sys

UNUSED_IMPORT_LINES = (
    "import os\n",
    "from tempfile import NamedTemporaryFile\n",
    "from pathlib import Path\n",
    "import yaml\n",
    "from databricks_dbt_factory.job_spec import replace_tasks_in_job_spec\n",
    "from databricks_dbt_factory.Utils import read_dbt_manifest\n",
    "BASE_PATH = str(Path(__file__).resolve().parent)\n",
)

# The golden-spec tests through the run_job_spec_test helper, up to the next kept test.
GOLDEN_SPEC_BLOCK = re.compile(
    r"\ndef test_create_job_spec_and_update\(.*?(?=\ndef test_resolver_uses_task_keys_map)",
    re.DOTALL,
)


def adapt(src: str) -> str:
    for line in UNUSED_IMPORT_LINES:
        if src.count(line) != 1:
            raise SystemExit(
                f"expected exactly one occurrence of {line!r} to strip, found {src.count(line)}. "
                "Upstream tests/test_dbt_factory.py imports changed; update this script."
            )
        src = src.replace(line, "", 1)
    src, count = GOLDEN_SPEC_BLOCK.subn("\n", src)
    if count != 1:
        raise SystemExit(
            f"expected exactly one golden-spec block to strip, found {count}. "
            "Upstream tests/test_dbt_factory.py structure changed; update this script."
        )
    if "job_spec" in src:
        raise SystemExit(
            "adapted test_dbt_factory.py still references job_spec; adaptation is incomplete."
        )
    return src.lstrip("\n")


def main() -> None:
    src_path, out_path = sys.argv[1], sys.argv[2]
    with open(src_path, "r", encoding="utf-8") as f:
        adapted = adapt(f.read())
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(adapted)


if __name__ == "__main__":
    main()
