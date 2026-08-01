# TiC Schottky free energy (phonopy + VASP)

Compute the **Schottky pair formation free energy** for TiC (2×2×2 supercells:
`nodef`, `cVac`, `2G`) with harmonic phonons (phonopy) and finite-displacement
VASP forces.

## Host

**Run VASP on Metis only** (`metis.mse.kth.se`).  
Do **not** run this pipeline on Leto. Scripts refuse hostname `*leto*`.

Default parallel budget on Metis: **7 concurrent jobs × 8 MPI ranks = 56 cores**.

## POTCAR (required, not in this repo)

VASP **POTCAR** files are **licensed** and are **not** included. Collaborators
and users must supply their own PAW potentials:

| need | detail |
|------|--------|
| sets | `PAW_PBE Ti` + `PAW_PBE C` (standard 08Apr2002 recommended) |
| order | **Ti then C** (matches POSCAR) |
| install | `nodef/POTCAR`, `cVac/POTCAR`, `2G/POTCAR` (identical content) |

```bash
# Example after you have a licensed potpaw_PBE tree:
export VASP_PP_PATH=/path/to/vasp/potentials
cat "${VASP_PP_PATH}/potpaw_PBE/Ti/POTCAR" \
    "${VASP_PP_PATH}/potpaw_PBE/C/POTCAR" \
  > nodef/POTCAR
cp -a nodef/POTCAR cVac/POTCAR 2G/POTCAR
```

Full instructions: **[docs/POTCAR.md](docs/POTCAR.md)**.

## Quick start (on Metis)

```bash
ssh metis
cd /path/to/phono   # or clone this repo
export PATH="$HOME/.local/bin:$PATH"

# 1) Install POTCARs (see docs/POTCAR.md) — required before VASP
# 2) Prerequisites
bash run_workflow.sh --only 0
# 3) Full pipeline, ≤56 cores
bash run_workflow.sh --auto-submit
```

See **[WORKFLOW.md](WORKFLOW.md)** for physics, steps, and environment variables.

## Layout

| path | role |
|------|------|
| `run_workflow.sh` | main entry (steps 0–6) |
| `scripts/` | prepare, Metis parallel pool, Schottky table |
| `templates/` | INCAR / KPOINTS / phonopy confs |
| `docs/POTCAR.md` | how to obtain and install PAW POTCARs |
| `nodef/` `cVac/` `2G/` | structures + staged `disp_*/` (add your POTCAR) |
| `results/` | Schottky tables |
