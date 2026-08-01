#!/bin/bash
# Static VASP launcher — Metis only (metis.mse.kth.se), NOT Leto.
# Prefer:  ssh metis && cd /slask/mehdin/dynamics/phono && bash scripts/run_local_parallel.sh --static
#
# Usage (ON METIS, from this folder):  bash r.sh

_hn=$(hostname -s 2>/dev/null || hostname)
case "${_hn,,}" in
  *leto*)
    echo "ERROR: this r.sh is for Metis, not Leto (host=${_hn})." >&2
    exit 2
    ;;
esac

source /opt/intel/oneapi/setvars.sh >/dev/null 2>&1 || true
export OMP_NUM_THREADS=1

nohup nice -n 19 mpirun -np 8 \
  -genv OMP_NUM_THREADS 1 \
  /prog/bin/vasp_std >> o.dat 2>&1 &
