# TiC Schottky free energy (phonopy + VASP)

Compute the **Schottky pair formation free energy** for TiC (2×2×2 supercells:
`nodef`, `cVac`, `2G`) with harmonic phonons (phonopy) and finite-displacement
VASP forces.

## Host

**Run VASP on Metis Cluster**

Default parallel budget: **7 concurrent jobs × 8 MPI ranks = 56 cores**.

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
| `CITATION.bib` | BibTeX for papers + this repository |
| `CITATION.cff` | GitHub citation metadata |
| `nodef/` `cVac/` `2G/` | structures + staged `disp_*/` (add your POTCAR) |
| `results/` | Schottky tables |

## How to cite

When using this workflow and the underlying defect physics, please cite:

1. **Smirnova, Nourazar & Korzhavyi**, *Phys. Rev. B* **109**, L060103 (2024)  
   — reconstructed **2G** metal-vacancy ground state.  
   DOI: [10.1103/PhysRevB.109.L060103](https://doi.org/10.1103/PhysRevB.109.L060103)

2. **Nourazar & Korzhavyi**, *Acta Materialia* **317**, 122538 (2026)  
   — Schottky formation energies and vacancy interactions with reconstruction.  
   DOI: [10.1016/j.actamat.2026.122538](https://doi.org/10.1016/j.actamat.2026.122538)

3. **This repository** (software / workflow)  
   — [https://github.com/mehDN/phono-tic-schottky](https://github.com/mehDN/phono-tic-schottky)

Ready-to-paste BibTeX is in **[`CITATION.bib`](CITATION.bib)** (keys `smirnova2024`,
`nourazar2026`, `nourazar2026phono`). GitHub also reads **[`CITATION.cff`](CITATION.cff)**
(sidebar “Cite this repository”).

```bibtex
@article{smirnova2024,
  author  = {Smirnova, Ekaterina and Nourazar, Mehdi and Korzhavyi, Pavel A.},
  title   = {Internal structure of metal vacancies in cubic carbides},
  journal = {Physical Review B},
  volume  = {109},
  number  = {6},
  pages   = {L060103},
  year    = {2024},
  doi     = {10.1103/PhysRevB.109.L060103}
}

@article{nourazar2026,
  author  = {Nourazar, Mehdi and Korzhavyi, Pavel Alexeevich},
  title   = {Configuration of {Schottky} defects in transition metal carbides},
  journal = {Acta Materialia},
  volume  = {317},
  pages   = {122538},
  year    = {2026},
  doi     = {10.1016/j.actamat.2026.122538}
}

@software{nourazar2026phono,
  author  = {Nourazar, Mehdi},
  title   = {{phono-tic-schottky}: Schottky formation free energy from phonopy and {VASP} for {TiC}},
  year    = {2026},
  url     = {https://github.com/mehDN/phono-tic-schottky}
}
```
