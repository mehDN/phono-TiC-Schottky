#!/usr/bin/env bash
# Count how many displacement VASP jobs have finished (vasprun.xml present).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for s in nodef cVac 2G; do
  done_n=0
  tot=0
  for d in "$ROOT/$s"/disp_*; do
    [[ -d "$d" ]] || continue
    tot=$((tot + 1))
    [[ -f "$d/vasprun.xml" ]] && done_n=$((done_n + 1))
  done
  printf '%-6s  %4d / %4d  vasprun.xml\n' "$s" "$done_n" "$tot"
done
