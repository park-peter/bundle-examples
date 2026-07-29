#!/bin/bash
# Vendor the databricks-dbt-factory core into the dbt-factory bundle template and example.
#
# bundle-examples cannot take a third-party runtime dependency, so the factory core is vendored.
# To keep it in sync with upstream mechanically (never hand-ported), this copies a CLI-stripped
# subset from a pinned upstream tag into the TEMPLATE, then mirrors it into the EXAMPLE so the two
# stay byte-identical (the .github/workflows/dbt-factory-sync.yml check enforces that equality).
#
# Usage: scripts/vendor_dbt_factory.sh <upstream-git-url> <tag>
#   scripts/vendor_dbt_factory.sh https://github.com/mwojtyczka/databricks-dbt-factory v0.3.1

set -euo pipefail

UPSTREAM_URL="${1:?upstream git url required}"
TAG="${2:?upstream tag required, e.g. v0.3.1}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_CORE="$REPO_ROOT/contrib/templates/dbt-factory/template/{{.project_name}}/src/databricks_dbt_factory"
EXAMPLE_CORE="$REPO_ROOT/contrib/dbt_factory/src/databricks_dbt_factory"

# The subset the PyDABs path uses. job_spec.py and main.py (the CLI / job-spec-writing surface)
# are intentionally excluded — the bundle reads the manifest via Utils.read_dbt_manifest and hands
# the generated tasks to PyDABs, so it never touches that code.
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

vendor_into() {
  local dest_core="$1"
  rm -rf "$dest_core"
  mkdir -p "$dest_core/notebook"
  for f in "${CORE_FILES[@]}"; do
    local src="$TMP/upstream/src/databricks_dbt_factory/$f"
    if [ ! -f "$src" ]; then
      echo "ERROR: expected upstream file missing: $f" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$dest_core/$f")"
    cp "$src" "$dest_core/$f"
  done
}

echo "Vendoring core into template and example ..."
vendor_into "$TEMPLATE_CORE"
vendor_into "$EXAMPLE_CORE"

echo "Formatting vendored core to this repo's style (ruff 0.9.1, line-length 120) ..."
uvx ruff@0.9.1 format --line-length 120 "$TEMPLATE_CORE" "$EXAMPLE_CORE"

cat <<EOF

Vendored databricks_dbt_factory core:
  from: $UPSTREAM_URL
  tag:  $TAG
  sha:  $RESOLVED_SHA

Next:
  1. Update the NOTICE 'Adapted from' line to $TAG ($RESOLVED_SHA) in both
     contrib/templates/dbt-factory/template/{{.project_name}}/NOTICE and contrib/dbt_factory/NOTICE.
  2. Regenerate golden fixtures + run both test suites.
EOF
