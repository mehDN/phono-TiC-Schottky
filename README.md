# TiC Schottky free energy (phonopy and VASP)

Compute the **Schottky pair formation free energy, entropy, and heat capacity**
for TiC (2×2×2 supercells: `nodef`, `cVac`, `2G`) with harmonic phonons
(phonopy) and finite displacement VASP forces — plus phonon band structures
and a Schottky combined band plot.



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

## Schottky formula

With \(N=32\) sites per sublattice:

\[
X_{\mathrm{S}}
  = X_{\mathrm{2G}} + X_{\mathrm{cVac}} - \tfrac{63}{32}\, X_{\mathrm{nodef}}
\]

applied to static DFT energies, phonon \(F_{\mathrm{vib}}\), \(U_{\mathrm{vib}}\),
\(S_{\mathrm{vib}}\), \(C_{V,\mathrm{vib}}\), and (sorted/interpolated) band
frequencies \(\omega(q,i)\). Total free energy:

\[
F^{\mathrm{f}}(T)=E^{\mathrm{f,DFT}}+\Delta F_{\mathrm{vib}}(T).
\]

Details: **[WORKFLOW.md](WORKFLOW.md)** §1 and §6.6.

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

# After forces finished (or already have FORCE_SETS):
bash run_workflow.sh --from 4
# thermal + Schottky F/S/Cv + bands only:
bash run_workflow.sh --thermal-only
# rebuild tables and PDFs only:
bash run_workflow.sh --schottky-only
bash run_workflow.sh --plot-only
```

Useful flags: `--skip-bands`, `--skip-plot`, `--skip-fc`, `--force-rebuild`.  
See `bash run_workflow.sh --help` and **[WORKFLOW.md](WORKFLOW.md)**.

## Main results (`results/`)

| output | description |
|--------|-------------|
| `schottky_free_energy.dat` / `.pdf` | \(F^{\mathrm{f}}(T)\) |
| `schottky_entropy.dat` / `.pdf` | \(\Delta S(T)\) |
| `schottky_heat_capacity.dat` / `.pdf` | \(\Delta C_V(T)\) |
| `schottky.dat` / `schottky_all.pdf` | combined table / 3-panel plot |
| `thermal_properties_{nodef,cVac,2G}.yaml` | phonopy thermal archives |
| `bands_{nodef,cVac,2G}.pdf` (+ `.yaml`) | individual phonon bands |
| `bands.pdf` | nodef \| cVac \| 2G side-by-side |
| `bands_schottky.pdf` (+ `.yaml`) | \(\omega_{\mathrm{S}}=\omega_{2G}+\omega_{\mathrm{cVac}}-(63/32)\omega_{\mathrm{nodef}}\) |

Per-structure band files also live under `nodef/`, `cVac/`, `2G/`
(`bands.conf`, `bands.yaml`, `bands.pdf`).

## Layout

| path | role |
|------|------|
| `run_workflow.sh` | main entry (steps 0–6) |
| `scripts/` | VASP pool, thermal, Schottky tables, bands, plots |
| `templates/` | INCAR / KPOINTS / mesh.conf / bands.conf |
| `docs/POTCAR.md` | how to obtain and install PAW POTCARs |
| `CITATION.bib` / `CITATION.cff` | citation metadata |
| `nodef/` `cVac/` `2G/` | structures + `disp_*/` (add your POTCAR) |
| `results/` | Schottky tables, bands, PDFs |

Key scripts:

| script | role |
|--------|------|
| `scripts/run_phonopy_thermal.py` | `thermal_properties.yaml` |
| `scripts/schottky_from_thermal.py` | Schottky \(F,S,C_V\) vs \(T\) |
| `scripts/plot_schottky.py` | Schottky PDFs |
| `scripts/run_phonopy_bands.py` | `bands.conf` / `bands.yaml` |
| `scripts/plot_bands.py` | per-structure + `bands.pdf` |
| `scripts/schottky_bands.py` | `bands_schottky.pdf` |
| `scripts/compute_schottky_thermal.sh` | standalone thermal+Schottky pipeline |

## How to cite

If you use this workflow or the underlying defect physics, please cite:

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
