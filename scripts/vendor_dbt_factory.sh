#!/bin/bash
# Vendor the databricks-dbt-factory core AND its core tests into the dbt-factory bundle template
# and example, so the bundle is self-contained (no runtime or test dependency on the upstream repo).
#
# Copies a CLI-stripped file subset from a pinned upstream tag into both the template and the
# example, formats it, and leaves the two byte-identical (enforced by
# .github/workflows/dbt-factory-sync.yml).
#
# Usage: scripts/vendor_dbt_factory.sh <upstream-git-url> <tag>
#   scripts/vendor_dbt_factory.sh https://github.com/mwojtyczka/databricks-dbt-factory v0.3.2

set -euo pipefail

UPSTREAM_URL="${1:?upstream git url required}"
TAG="${2:?upstream tag required, e.g. v0.3.2}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_ROOT="$REPO_ROOT/contrib/templates/dbt-factory/template/{{.project_name}}"
EXAMPLE_ROOT="$REPO_ROOT/contrib/dbt_factory"

# The core subset the PyDABs path uses. Omits the upstream CLI files (job_spec.py, main.py).
CORE_FILES=(
  "__about__.py"
  "__init__.py"
  "DbtFactory.py"
  "DbtTask.py"
  "TaskFactory.py"
  "Utils.py"
  "notebook/run_dbt_command.py"
)

# Upstream tests that exercise only the vendored core. Copied verbatim.
TEST_FILES=(
  "conftest.py"
  "test_utils.py"
  "test_dbt_task.py"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $UPSTREAM_URL@$TAG ..."
git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM_URL" "$TMP/upstream"
RESOLVED_SHA="$(git -C "$TMP/upstream" rev-parse HEAD)"

# Assemble and format the vendored files in a staging dir, then copy them into the destinations
# last, so a failure never leaves a destination deleted or half-written.
STAGED_CORE="$TMP/staged/src/databricks_dbt_factory"
STAGED_TESTS="$TMP/staged/tests"
mkdir -p "$STAGED_CORE/notebook" "$STAGED_TESTS"

for f in "${CORE_FILES[@]}"; do
  src="$TMP/upstream/src/databricks_dbt_factory/$f"
  if [ ! -f "$src" ]; then
    echo "ERROR: expected upstream file missing: src/databricks_dbt_factory/$f" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$STAGED_CORE/$f")"
  cp "$src" "$STAGED_CORE/$f"
done

for f in "${TEST_FILES[@]}"; do
  src="$TMP/upstream/tests/$f"
  if [ ! -f "$src" ]; then
    echo "ERROR: expected upstream file missing: tests/$f" >&2
    exit 1
  fi
  cp "$src" "$STAGED_TESTS/$f"
done

# test_dbt_factory.py also imports job_spec (a CLI file this bundle does not vendor) for four
# golden-spec tests. Drop those tests, that helper, and the imports they use; keep the DAG/gating
# tests that exercise only the core.
python3 "$REPO_ROOT/scripts/vendor_test_dbt_factory.py" \
  "$TMP/upstream/tests/test_dbt_factory.py" "$STAGED_TESTS/test_dbt_factory.py"

# Keep this ruff version in sync with .github/workflows/fmt.yml.
echo "Formatting vendored files to this repo's style (ruff 0.9.1, line-length 120) ..."
uvx ruff@0.9.1 format --line-length 120 "$TMP/staged"

echo "Vendoring core and tests into template and example ..."
for root in "$TEMPLATE_ROOT" "$EXAMPLE_ROOT"; do
  rm -rf "$root/src/databricks_dbt_factory"
  mkdir -p "$root/src"
  cp -R "$STAGED_CORE" "$root/src/databricks_dbt_factory"
  for f in "${TEST_FILES[@]}" "test_dbt_factory.py"; do
    cp "$STAGED_TESTS/$f" "$root/tests/$f"
  done
done

cat <<EOF

Vendored databricks_dbt_factory core and tests:
  from: $UPSTREAM_URL
  tag:  $TAG
  sha:  $RESOLVED_SHA

Next:
  1. Update the NOTICE 'Vendored from' line to $TAG ($RESOLVED_SHA) in both
     contrib/templates/dbt-factory/template/{{.project_name}}/NOTICE and contrib/dbt_factory/NOTICE.
  2. Update the version pin in tests/test_vendored_core.py to match $TAG, in both the template and
     the example (kept identical by dbt-factory-sync.yml).
  3. Run the example test suite: (cd contrib/dbt_factory && uv run pytest tests)
EOF
