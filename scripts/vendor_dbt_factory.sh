#!/bin/bash
# Vendor the databricks-dbt-factory core into the dbt-factory bundle template and example.
#
# Copies a CLI-stripped file subset from a pinned upstream tag into both the template and the
# example, formats it, and leaves the two byte-identical (enforced by
# .github/workflows/dbt-factory-sync.yml).
#
# Usage: scripts/vendor_dbt_factory.sh <upstream-git-url> <tag>
#   scripts/vendor_dbt_factory.sh https://github.com/mwojtyczka/databricks-dbt-factory v0.3.1

set -euo pipefail

UPSTREAM_URL="${1:?upstream git url required}"
TAG="${2:?upstream tag required, e.g. v0.3.1}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_CORE="$REPO_ROOT/contrib/templates/dbt-factory/template/{{.project_name}}/src/databricks_dbt_factory"
EXAMPLE_CORE="$REPO_ROOT/contrib/dbt_factory/src/databricks_dbt_factory"

# The subset the PyDABs path uses. Omits the upstream CLI files (job_spec.py, main.py).
CORE_FILES=(
  "__about__.py"
  "__init__.py"
  "DbtFactory.py"
  "DbtTask.py"
  "TaskFactory.py"
  "Utils.py"
  "notebook/run_dbt_command.py"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $UPSTREAM_URL@$TAG ..."
git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM_URL" "$TMP/upstream"
RESOLVED_SHA="$(git -C "$TMP/upstream" rev-parse HEAD)"

# Assemble and format the vendored subset in a staging dir, then copy it into the destinations
# last, so a failure never leaves a destination deleted or half-written.
STAGED="$TMP/staged"
mkdir -p "$STAGED/notebook"
for f in "${CORE_FILES[@]}"; do
  src="$TMP/upstream/src/databricks_dbt_factory/$f"
  if [ ! -f "$src" ]; then
    echo "ERROR: expected upstream file missing: $f" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$STAGED/$f")"
  cp "$src" "$STAGED/$f"
done

# Keep this ruff version in sync with .github/workflows/fmt.yml.
echo "Formatting vendored core to this repo's style (ruff 0.9.1, line-length 120) ..."
uvx ruff@0.9.1 format --line-length 120 "$STAGED"

echo "Vendoring core into template and example ..."
for dest_core in "$TEMPLATE_CORE" "$EXAMPLE_CORE"; do
  rm -rf "$dest_core"
  mkdir -p "$(dirname "$dest_core")"
  cp -R "$STAGED" "$dest_core"
done

cat <<EOF

Vendored databricks_dbt_factory core:
  from: $UPSTREAM_URL
  tag:  $TAG
  sha:  $RESOLVED_SHA

Next:
  1. Update the NOTICE 'Vendored from' line to $TAG ($RESOLVED_SHA) in both
     contrib/templates/dbt-factory/template/{{.project_name}}/NOTICE and contrib/dbt_factory/NOTICE.
  2. Run the example test suite: (cd contrib/dbt_factory && uv run pytest tests)
EOF
