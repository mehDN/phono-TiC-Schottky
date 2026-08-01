#!/usr/bin/env bash
# Run all disp_* for this structure on Metis only (not Leto), core-capped.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRUCT="$(basename "$(pwd)")"
# shellcheck source=cluster_env.sh
source "$ROOT/scripts/cluster_env.sh"
require_metis_host hard || exit 2
exec bash "$ROOT/scripts/run_local_parallel.sh" "$STRUCT"
