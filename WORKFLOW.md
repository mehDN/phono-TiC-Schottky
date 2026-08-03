# Schottky defect free energy from phonopy (TiC, 2×2×2)

Workflow to compute the **Schottky pair formation free energy** for TiC using
harmonic phonons (phonopy + VASP), for:

| structure | folder  | composition | atoms | meaning                          |
|-----------|---------|-------------|-------|----------------------------------|
| perfect   | `nodef` | Ti₃₂C₃₂     | 64    | defect-free 2×2×2 supercell      |
| C vacancy | `cVac`  | Ti₃₂C₃₁     | 63    | carbon monovacancy               |
| 2G metal  | `2G`    | Ti₃₁C₃₂     | 63    | reconstructed Ti vacancy (2G)     |

Structures are taken from the relaxed POSCARs in `phono_222/`
(consistent lattice *a* = 8.6753246 Å).

> **Compute host: Metis only**  
> Run all local VASP work on **`metis.mse.kth.se`**.  
> Do **not** run this pipeline on **Leto** (`leto.mse.kth.se`).  
> Scripts refuse hostname `*leto*` (and print how to `ssh metis`).

> **POTCAR not included**  
> VASP PAW potentials are licensed and are **not** in this repository.  
> Install your own before running VASP — see **[docs/POTCAR.md](docs/POTCAR.md)**.

---

## 1. Physics (from the papers)

### 1.1 Static Schottky formation energy

**Acta Materialia** (Nourazar & Korzhavyi) and **PRB 109, L060103**
(Smirnova, Nourazar, Korzhavyi) define the Schottky formation energy for a
*single* supercell that already contains a dissociated Me–X vacancy pair as

\[
E^{\mathrm{f}}_{\mathrm{Schottky}}
  = E(\mathrm{Me}_{N-1}\mathrm{X}_{N-1})
  - \frac{N-1}{N}\, E(\mathrm{Me}_{N}\mathrm{X}_{N}),
\]

with \(N\) = number of sites on one sublattice.

Here we use **two separate supercells** (one C vacancy, one 2G Ti vacancy)
that together make one Schottky pair. Atom counting:

- perfect: \(2N = 64\) atoms, \(N = 32\)
- defects: \(63 + 63 = 126 = (2N-1)\) atoms total vs perfect formula units

so the equivalent expression is

\[
\boxed{
E^{\mathrm{f}}_{\mathrm{Schottky}}
  = E_{\mathrm{2G}} + E_{\mathrm{cVac}}
  - \frac{2N-1}{N}\, E_{\mathrm{nodef}}
  = E_{\mathrm{2G}} + E_{\mathrm{cVac}} - \frac{63}{32}\, E_{\mathrm{nodef}}
}
\]

with \(63/32 = 1.96875\).

Static DFT on the present POSCARs (from leftover `OUTCAR`s in `phono_222`)
gives roughly \(\sim 5\) eV for 2G+cVac, consistent with the papers
(unreconstructed ~7.5 eV, 2G reconstruction lowers by ~3.5 eV).

### 1.2 Vibrational / zero-point contribution (what phonopy provides)

In the harmonic approximation phonopy gives, **per supercell**, the
vibrational Helmholtz free energy \(F_{\mathrm{vib}}(T)\) (includes ZPE),
internal energy \(U_{\mathrm{vib}}(T)\), entropy \(S_{\mathrm{vib}}(T)\), and
heat capacity \(C_{V,\mathrm{vib}}(T)\):

\[
F_{\mathrm{vib}}(T)
  = \frac12\sum_{\mathbf{q}\nu}\hbar\omega_{\mathbf{q}\nu}
  + k_{\mathrm{B}}T\sum_{\mathbf{q}\nu}
    \ln\!\bigl[1-e^{-\hbar\omega_{\mathbf{q}\nu}/k_{\mathrm{B}}T}\bigr].
\]

At \(T=0\), \(F_{\mathrm{vib}} = U_{\mathrm{vib}} = E_{\mathrm{ZPE}}\) and
\(S_{\mathrm{vib}}=C_V=0\).

Apply the **same atom-balance factor** to every extensive phonon quantity \(X\):

\[
\boxed{
X_{\mathrm{Schottky}}(T)
  = X_{\mathrm{2G}}(T)
  + X_{\mathrm{cVac}}(T)
  - \frac{63}{32}\, X_{\mathrm{nodef}}(T)
}
\]

with \(X \in \{F_{\mathrm{vib}},\, U_{\mathrm{vib}},\, S_{\mathrm{vib}},\, C_{V,\mathrm{vib}},\, E_{\mathrm{ZPE}}\}\).

### 1.3 Total temperature-dependent Schottky free energy

\[
\boxed{
F^{\mathrm{f}}_{\mathrm{Schottky}}(T)
  = E^{\mathrm{f,DFT}}_{\mathrm{Schottky}}
  + \Delta F^{\mathrm{vib}}_{\mathrm{Schottky}}(T)
}
\]

where \(E^{\mathrm{f,DFT}}\) uses **static** total energies (same POSCARs,
tight electronic convergence, no ionic relaxation during force jobs).
Static DFT does **not** contribute to \(S\) or \(C_V\) (harmonic vib only).

Phonopy units (per supercell): free energy / energy in **kJ/mol**; entropy
and \(C_V\) in **J K⁻¹ mol⁻¹**. Convert energies to eV with

\[
1\,\mathrm{kJ\,mol^{-1}} = 1/96.485336459\,\mathrm{eV} \approx 0.01036427\,\mathrm{eV}.
\]

Entropy / \(C_V\): \(1\,\mathrm{J\,K^{-1}\,mol^{-1}} = 1/96485.336\,\mathrm{eV\,K^{-1}}\).

### 1.4 Schottky phonon bands

The same linear combination is applied to phonon frequencies along a common
high-symmetry path (Γ–X–M–Γ–R in the **supercell** reciprocal basis,
`DIM = 1 1 1`):

\[
\boxed{
\omega_{\mathrm{S}}(q,i)
  = \omega_{\mathrm{2G}}(q,i)
  + \omega_{\mathrm{cVac}}(q,i)
  - \frac{63}{32}\, \omega_{\mathrm{nodef}}(q,i)
}
\]

Mode counts differ (nodef: \(3\times 64=192\), defects: \(3\times 63=189\)).
Degrees of freedom still balance: \(189+189 = 1.96875\times 192 = 378\).
At each \(q\), frequencies are **sorted** ascending and the nodef spectrum is
**interpolated** in band-index fraction onto 189 bands before combining.

The result is a **difference spectrum** (not a set of physical eigenmodes of
one supercell). Values can be **negative**; plots draw a zero line.

---

## 2. Why `phono_222` and `zerop` are not correct

| issue | `phono_222` | `zerop` | fix in this workflow |
|-------|-------------|---------|----------------------|
| VASP mode for forces | `IBRION = 8` (DFPT) mixed with hundreds of finite-displacement `POSCAR-*` | same / mixed | **finite displacement**: `IBRION = -1`, `NSW = 0` |
| DIM / supercell definition | `DIM = 1 1 1` on already-2×2×2 cell (OK) but mesh configs inconsistent | `DIM` randomly `1 1 1`, `2 2 2`, or FCC primitive `-2 2 2 …` for the *same* 64-atom POSCAR | one convention: **cell = supercell, `DIM = 1 1 1`** |
| Symmetry | P1 because MD-relaxed coordinates break ideal Fm-3m | same | keep P1 for defects; document displacement count ≈ 3×N_atoms (or 6× with ±) |
| Schottky script | factor 1.96875 is right, but applied only to vib energies, not full \(F\) | incomplete FORCE_SETS / missing thermal for some folders | `scripts/schottky_from_thermal.py` |
| Quantity used | `energy` column (vib internal energy) in `get_Schtkyout.sh` | N/A | use **`free_energy`** for \(\Delta F\), **`energy`** only for \(\Delta U\) / ZPE |
| Static DFT | not combined with vib result | OUTCARs from different settings | separate static single-point on each POSCAR |
| Mesh for thermal | `MP = 32 32 32` on large cell | `48 48 48`, `65 65 65`, `67 67 67` mixed | one dense mesh + convergence check |
| POTCAR / ENCUT consistency | ENCUT 500 OK | sometimes 400 eV AIMD settings bleed in | fixed templates ENCUT=500 |

**Important limitation retained intentionally:** the POSCARs are already 2×2×2
supercells (~8.67 Å). With `DIM = 1 1 1` the force-constant range cannot
exceed that cell. For production-quality phonons one would rebuild from a
primitive cell with `DIM = 2 2 2` or `3 3 3` (and ideally a 3×3×3 defect
supercell as in the papers, \(N=108\)). This workflow matches the user’s
requested 64/63-atom cells.

---

## 3. Directory layout

```
phono/
├── WORKFLOW.md                 # this file
├── README.md                   # short overview + cite
├── run_workflow.sh             # *** main entry point (run everything) ***
├── templates/
│   ├── INCAR.static            # single-point total energy
│   ├── INCAR.forces            # finite-displacement forces (phonopy)
│   ├── KPOINTS                 # Gamma 3×3×3 for 2×2×2 supercell
│   ├── mesh.conf               # thermal properties mesh
│   ├── bands.conf / band.conf  # phonon band path (Γ–X–M–Γ–R)
│   └── disp.conf               # create displacements
├── scripts/
│   ├── cluster_env.sh              # Metis defaults, host checks (not Leto)
│   ├── run_local_parallel.sh       # Metis core-capped parallel VASP pool
│   ├── submit_all_structures.sh
│   ├── 01_create_displacements.sh
│   ├── 02_prepare_vasp_jobs.sh
│   ├── 03_collect_force_sets.sh    # phonopy-init -f (v4)
│   ├── 04_thermal_properties.sh    # → thermal_properties.yaml
│   ├── 05_static_energies.sh
│   ├── run_phonopy_thermal.py      # phonopy API thermal (v4)
│   ├── run_phonopy_bands.py        # bands.conf + bands.yaml per structure
│   ├── schottky_from_thermal.py    # F, S, Cv Schottky tables
│   ├── schottky_bands.py           # Schottky band combo + PDF
│   ├── plot_schottky.py            # F/S/Cv PDFs
│   ├── plot_bands.py               # per-structure + combined bands.pdf
│   ├── compute_schottky_thermal.sh # FORCE_SETS → thermal → Schottky (+plots)
│   ├── count_vasp_progress.sh
│   └── run_demo_from_phono222.sh
├── docs/
│   └── POTCAR.md
├── CITATION.bib / CITATION.cff
├── nodef/   POSCAR (64); FORCE_SETS; thermal_properties.yaml; bands.*
├── cVac/    POSCAR (63); …
├── 2G/      POSCAR (63); …
└── results/   # tables, yaml archives, PDFs (see §6.6)
```

Path on the shared filesystem (visible from Metis and other MSE machines):

```text
/slask/mehdin/dynamics/phono
```

---

## 4. POTCAR (required — not in git)

This project needs a concatenated **PBE PAW** `POTCAR` with **Ti then C**
(matching the POSCAR species line). Files are **not committed** (see `.gitignore`
and VASP license terms).

| location | role |
|----------|------|
| `nodef/POTCAR`, `cVac/POTCAR`, `2G/POTCAR` | structure-level (identical content) |
| `*/static/POTCAR`, `*/disp_*/POTCAR` | copied by prepare scripts from the structure root |

**Minimal install** (after you have a licensed `potpaw_PBE` tree):

```bash
export VASP_PP_PATH=/path/to/vasp/potentials
cat "${VASP_PP_PATH}/potpaw_PBE/Ti/POTCAR" \
    "${VASP_PP_PATH}/potpaw_PBE/C/POTCAR" \
  > nodef/POTCAR
cp -a nodef/POTCAR cVac/POTCAR 2G/POTCAR

# Optional: re-stage jobs so every disp_*/static has a copy
bash scripts/05_static_energies.sh
bash scripts/02_prepare_vasp_jobs.sh
```

Recommended datasets: `PAW_PBE Ti 08Apr2002` and `PAW_PBE C 08Apr2002`.  
Full download / site-path / consistency notes: **[docs/POTCAR.md](docs/POTCAR.md)**.

Step 0 of `run_workflow.sh` fails with a clear error if any structure is missing
`POTCAR`.

---

## 5. Host: Metis only (not Leto)

| | |
|--|--|
| **Correct host** | `metis.mse.kth.se` (short name `metis`) |
| **Wrong host** | `leto.mse.kth.se` — **do not run** this pipeline there |
| **Why** | VASP is launched as a **local** `mpirun` pool on Metis (no SLURM). Leto is a different machine; `wc_114/run_leto.sh` is a separate project. |
| **How scripts enforce it** | `scripts/cluster_env.sh` provides `is_metis_host` / `is_leto_host` / `require_metis_host`. Batch submit, `run_local_parallel.sh`, and every staged `r.sh` **exit with an error** on Leto. |

```bash
# Always log into Metis first
ssh metis
# or:  ssh metis.mse.kth.se
cd /slask/mehdin/dynamics/phono
hostname    # should print something containing "metis"
```

If you start a job on Leto by mistake you should see:

```text
ERROR: this phono pipeline must run on Metis, not Leto.
  Correct:  ssh metis
```

Override (not recommended): `FORCE_HOST=1` — still prints a warning.

---

## 6. Usage: `run_workflow.sh` (recommended)

All steps are orchestrated by **`phono/run_workflow.sh`**. Work **on Metis**
from the `phono/` directory:

```bash
ssh metis
cd /slask/mehdin/dynamics/phono
bash run_workflow.sh --help
```

### 6.1 Parallel local VASP on Metis (56-core cap)

On Metis, `hostname` contains `metis` → **`RUN_MODE=metis`** (no SLURM).
Jobs run with Intel oneAPI `mpirun` + `/prog/bin/vasp_std`, at low priority
(`nice -n 19`), with CPU pinning so concurrent jobs use disjoint cores.

Launch mechanics are **adapted from** the batch scripts under
`/slask/mehdin/dynamics/wc_114/` (shared disk), but the **target machine is
Metis**, not Leto.

| setting | default | meaning |
|---------|---------|---------|
| host | **metis** | refused on **leto** |
| `NPROC` | **8** | MPI ranks per VASP (`mpirun -np 8`) |
| `MAX_JOBS` | **7** | concurrent VASP instances |
| total | **56** | `MAX_JOBS × NPROC` cores, pinned from `CORE_BASE=0` (cores 0–55) |
| `NPAR` / `NSIM` | **2** / **4** | injected into each job `INCAR` |
| `NICE` | **19** | low priority vs interactive users |
| `VASP` | `/prog/bin/vasp_std` | after `source /opt/intel/oneapi/setvars.sh` |
| per-job log | `disp_*/o.dat` | stdout/stderr for each displacement |
| master log | `results/local_runs/parallel_*.log` | batch driver |

Resume is safe: directories that already have `vasprun.xml` are skipped.

```bash
ssh metis
cd /slask/mehdin/dynamics/phono

# full pipeline: static + forces under the 56-core cap
bash run_workflow.sh --auto-submit

# force pool only (after step 3 prepared)
bash scripts/submit_all_structures.sh
# or background:
# nohup bash scripts/run_local_parallel.sh > results/local_runs/nohup.out 2>&1 &

# status / dry-run / progress
bash scripts/run_local_parallel.sh --status
bash scripts/run_local_parallel.sh --dry-run
bash scripts/count_vasp_progress.sh

# optional: more concurrent jobs, fewer ranks each (still 56 cores)
MAX_JOBS=14 NPROC=4 bash scripts/02_prepare_vasp_jobs.sh
MAX_JOBS=14 NPROC=4 bash scripts/submit_all_structures.sh
```

After changing `NPROC` / `MAX_JOBS`, re-run `02_prepare_vasp_jobs.sh` so
`r.sh` and `NPAR`/`NSIM` stay consistent.

### 6.2 Common commands

| command | what it does |
|---------|----------------|
| `bash run_workflow.sh` | Full pipeline; **prompts** before local VASP on Metis |
| `bash run_workflow.sh --auto-submit` | Run static + force jobs without asking; waits for `vasprun.xml` |
| `bash run_workflow.sh --from 4` | FORCE_SETS → thermal → Schottky F/S/Cv + bands + PDFs |
| `bash run_workflow.sh --only 2` | Run a single step (0–6) |
| `bash run_workflow.sh --skip-static` | Skip staging static DFT (step 1) |
| `bash run_workflow.sh --thermal-only` | Steps **5–6** only (needs `FORCE_SETS`) |
| `bash run_workflow.sh --schottky-only` | Step **6** only (thermal yaml + bands + plots) |
| `bash run_workflow.sh --plot-only` | Replot Schottky + band PDFs (and Schottky bands) from existing data |
| `bash run_workflow.sh --skip-fc` | Skip step 4 (`FORCE_SETS` collection) |
| `bash run_workflow.sh --force-rebuild` | Re-collect `FORCE_SETS` even if present |
| `bash run_workflow.sh --skip-plot` | Skip all PDF generation in step 6 |
| `bash run_workflow.sh --skip-bands` | Skip phonon bands / Schottky bands in step 6 |
| `bash run_workflow.sh --demo` | Schottky tables from existing `../phono_222` thermals (no VASP) |
| `bash scripts/submit_all_structures.sh` | Metis force pool only (all structures) |
| `bash scripts/run_local_parallel.sh --status` | Pending / done / live `vasp_std` count |
| `bash scripts/compute_schottky_thermal.sh` | Standalone: FORCE_SETS → thermal → Schottky (+plots) |

### 6.3 Pipeline steps (inside `run_workflow.sh`)

| step | action |
|------|--------|
| 0 | Prerequisites (POSCAR/POTCAR, phonopy, **host = Metis**, core plan) |
| 1 | Stage (and optionally run) static DFT → `*/static/` on Metis |
| 2 | Create finite displacements (`phonopy-init -d` / v3 `phonopy -d`) |
| 3 | Prepare `disp_*/` jobs; optionally run Metis pool and wait |
| 4 | Collect `FORCE_SETS` (`phonopy-init -f`); skip if already present unless `--force-rebuild` |
| 5 | Thermal properties → `*/thermal_properties.yaml` + `results/thermal_properties_*.yaml` |
| 6 | **6a** Schottky \(F\), \(S\), \(C_V\) tables → `results/schottky_*.dat` |
|   | **6b** Plot \(F,S,C_V\) vs \(T\) → `results/schottky_*.pdf` |
|   | **6c** Phonon bands (nodef, cVac, 2G) → `bands.conf` / `bands.yaml` / `bands.pdf` |
|   | **6d** Combined band plot → `results/bands.pdf` |
|   | **6e** Schottky bands → `results/bands_schottky.yaml` + `bands_schottky.pdf` |

If force jobs are not started, the script **stops after step 3** so incomplete
force sets are not collected. Resume with:

```bash
bash run_workflow.sh --from 4
```

### 6.4 Environment overrides

```bash
# phonopy displacement amplitude (Å)
AMP=0.015 bash run_workflow.sh --from 2

# thermal mesh / temperature grid
MESH="48 48 48" TMAX=3000 TSTEP=10 bash run_workflow.sh --from 5
# or only thermal + Schottky + bands:
MESH="32 32 32" bash run_workflow.sh --thermal-only

# band path sampling density
BAND_POINTS=101 bash run_workflow.sh --schottky-only

# Metis core budget (defaults: 7 jobs × 8 ranks = 56 cores)
MAX_JOBS=7 NPROC=8 bash run_workflow.sh --auto-submit

# pin starting core (default 0 → use cores 0–55)
CORE_BASE=0 MAX_JOBS=7 NPROC=8 bash scripts/submit_all_structures.sh

# Static TOTEN in eV for step 6 (skip scraping */static/OUTCAR)
EDFT_NODEF=-588.59548361 EDFT_CVAC=-579.41447515 EDFT_2G=-574.37299057 \
  bash run_workflow.sh --only 6

# SLURM only if you intentionally move to another site (not Metis/Leto)
RUN_MODE=slurm ACCOUNT=myalloc NODES=1 NTASKS=32 WALLTIME=24:00:00 \
  VASP_CMD="mpprun vasp" bash run_workflow.sh --auto-submit
```

### 6.5 PATH and finding phonopy (v3 / v4)

Phonopy is often installed with `pip install --user` so the CLI lands in
**`~/.local/bin`**, which is **not always on `PATH`**. That produces:

```text
[error] phonopy not on PATH (needed for steps 2, 4, 5)
```

**What the scripts do automatically**

1. Prepend `$HOME/.local/bin` to `PATH` at the start of `run_workflow.sh`
   and of force / thermal scripts.
2. Resolve the binary in this order:
   - `phonopy` already on `PATH`
   - `$HOME/.local/bin/phonopy` if executable
   - `python3.13 -m phonopy` / `python3 -m phonopy` if the module imports
3. Export `PHONOPY_BIN` and (v4) `PHONOPY_INIT_BIN` for child scripts.
4. Thermal and band calculations use the **Python API**
   (`run_phonopy_thermal.py`, `run_phonopy_bands.py`) with
   `primitive_matrix="P"` so the input 2×2×2 cell is kept as given.

**Phonopy v4 note:** setup flags moved to `phonopy-init` (`-d`, `-f`);
phonon calculations use `phonopy`. This repo supports both.

**Permanent shell fix (recommended once):**

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

**Install / reinstall if missing:**

```bash
python3 -m pip install --user 'phonopy>=2.20' matplotlib pyyaml
# on Metis often: python3.13 -m pip install --user phonopy matplotlib pyyaml
which phonopy phonopy-init
```

**Override explicitly:**

```bash
export PHONOPY_BIN="$HOME/.local/bin/phonopy"
export PHONOPY_INIT_BIN="$HOME/.local/bin/phonopy-init"
bash run_workflow.sh
```

### 6.6 Outputs of step 5–6 (`results/`)

#### Thermal (per structure)

| file | content |
|------|---------|
| `nodef\|cVac\|2G/thermal_properties.yaml` | phonopy \(F,U,S,C_V\) vs \(T\) |
| `results/thermal_properties_{nodef,cVac,2G}.yaml` | copies |

#### Schottky thermodynamics vs \(T\)

| file | content |
|------|---------|
| `results/schottky_free_energy.dat` | \(T\), \(\Delta F_{\mathrm{vib}}\), \(E_{\mathrm{DFT}}\), \(F^{\mathrm{f}}\), \(U\) [eV] |
| `results/schottky_entropy.dat` | \(T\), \(\Delta S\) [eV/K and J K⁻¹ mol⁻¹] |
| `results/schottky_heat_capacity.dat` | \(T\), \(\Delta C_V\) [eV/K and J K⁻¹ mol⁻¹] |
| `results/schottky.dat` | combined table (all columns) |
| `results/schottky_free_energy.pdf` | plot \(F(T)\) |
| `results/schottky_entropy.pdf` | plot \(S(T)\) |
| `results/schottky_heat_capacity.pdf` | plot \(C_V(T)\) |
| `results/schottky_all.pdf` | three panels in one figure |

Static energies: scraped from `*/static/OUTCAR`, else
`results/static_energies.dat` / `static_energies.example.dat`, else
`EDFT_*` env vars. Without DFT, \(F^{\mathrm{f}}\) is vib-only.

#### Phonon bands (per structure + Schottky)

Path (supercell reciprocal coords, `DIM = 1 1 1`):
**Γ → X → M → Γ → R** (`templates/bands.conf`).

| file | content |
|------|---------|
| `{nodef,cVac,2G}/bands.conf` | band path used |
| `{nodef,cVac,2G}/bands.yaml` | phonopy band structure (`band.yaml` alias) |
| `{nodef,cVac,2G}/bands.pdf` | individual band plot |
| `results/bands_{nodef,cVac,2G}.{yaml,conf,pdf}` | archives |
| `results/nodef_bands.pdf` (etc.) | alias of per-structure PDF |
| `results/bands.pdf` | **nodef \| cVac \| 2G** side-by-side |
| `results/bands_schottky.yaml` | \(\omega_{\mathrm{S}}=\omega_{2G}+\omega_{\mathrm{cVac}}-(63/32)\omega_{\mathrm{nodef}}\) |
| `results/bands_schottky.pdf` | Schottky band difference plot |
| `results/bands_schotcky.pdf` | same PDF (spelling alias) |

Standalone replot / recompute:

```bash
# Schottky F, S, Cv plots only
python3.13 scripts/plot_schottky.py --results-dir results

# Individual + combined band PDFs
python3.13 scripts/plot_bands.py --results-dir results

# Schottky band combination + PDF
python3.13 scripts/schottky_bands.py --results-dir results

# Full step 6 redraw
bash run_workflow.sh --plot-only
```

---

## 7. Manual step-by-step (same as `run_workflow.sh`, if needed)

Use this only if you prefer to drive scripts individually. Prefer §6 otherwise.
**All VASP steps below assume you are already on Metis.**

```bash
ssh metis
cd /slask/mehdin/dynamics/phono
export PATH="$HOME/.local/bin:$PATH"
```

### Step 0 — prerequisites

```bash
python3 -m pip install --user 'phonopy>=2.20'   # if needed
# POTCAR: see §4 and docs/POTCAR.md (Ti then C, PBE PAW)
bash run_workflow.sh --only 0                   # host + POSCAR + POTCAR + phonopy
# Expect: hostname=metis, RUN_MODE=metis, TARGET: Metis only (not Leto)
```

### Step 1 — static DFT total energies (for \(E^{\mathrm{f,DFT}}\))

```bash
bash scripts/05_static_energies.sh
bash scripts/run_local_parallel.sh --static     # Metis pool; refuses Leto
```

### Step 2 — generate finite displacements (phonopy)

```bash
bash scripts/01_create_displacements.sh
# equivalent:  phonopy -d --dim="1 1 1" --amplitude=0.01 -c POSCAR
```

Produces `POSCAR-001…`, `SPOSCAR`, `phonopy_disp.yaml`.

Because relaxed defect cells have **P1** symmetry, expect:

- nodef: ~192 or ~384 displacements (depending on ± settings)
- cVac / 2G: ~189 or ~378

### Step 3 — VASP force calculations on every displacement (Metis)

```bash
bash scripts/02_prepare_vasp_jobs.sh
# Metis only (≤56 cores, MAX_JOBS=7 × NPROC=8) — not Leto:
bash scripts/submit_all_structures.sh
# monitor:
bash scripts/run_local_parallel.sh --status
bash scripts/count_vasp_progress.sh
```

Each job uses `INCAR.forces` (`IBRION=-1`, `NSW=0`, tight `EDIFF`, `NPAR=2`,
`NSIM=4`). Staged `r.sh` launches with `mpirun -np 8` and **refuses Leto**.
**Do not relax** displaced cells.

### Step 4 — build FORCE_SETS (and optional FORCE_CONSTANTS)

After all `vasprun.xml` exist:

```bash
bash scripts/03_collect_force_sets.sh
# phonopy v4: phonopy-init -f disp_*/vasprun.xml
```

### Step 5 — thermal properties (incl. ZPE)

```bash
bash scripts/04_thermal_properties.sh
# or: python3.13 scripts/run_phonopy_thermal.py --mesh 32 32 32 --tmax 2000 --tstep 10
```

Writes `*/thermal_properties.yaml` (and copies under `results/`).
Near-zero acoustic frequencies at Γ (~10⁻³ THz) are OK; large imaginary
modes mean the structure is unstable or forces are bad.

### Step 6 — Schottky \(F\), \(S\), \(C_V\), plots, and bands

```bash
# Preferred: full step 6 via the orchestrator
bash run_workflow.sh --schottky-only
# or after forces:  bash run_workflow.sh --from 4

# Manual pieces:
python3 scripts/schottky_from_thermal.py \
  --nodef nodef/thermal_properties.yaml \
  --cvac  cVac/thermal_properties.yaml \
  --twog  2G/thermal_properties.yaml \
  --edft-nodef  <TOTEN_eV> \
  --edft-cvac   <TOTEN_eV> \
  --edft-2g     <TOTEN_eV> \
  --out-dir results \
  --out results/schottky.dat

python3.13 scripts/plot_schottky.py --results-dir results

python3.13 scripts/run_phonopy_bands.py --copy-to results
python3.13 scripts/plot_bands.py --results-dir results
python3.13 scripts/schottky_bands.py --results-dir results
# → results/bands_schottky.pdf  (and bands_schotcky.pdf alias)
```

---

## 8. Recommended VASP settings (templates)

**Forces (phonopy)** — base template plus Metis parallel tags injected at prepare:

```
PREC = Accurate
ENCUT = 500
EDIFF = 1e-8
IBRION = -1
NSW = 0
ISMEAR = 0
SIGMA = 0.05
LREAL = .FALSE.
ADDGRID = .TRUE.
LWAVE = .FALSE.
LCHARG = .FALSE.
NPAR = 2          # set by 02_prepare for NPROC=8
NSIM = 4
```

**KPOINTS:** Gamma-centred `3×3×3` for this 2×2×2 supercell (papers use
`5×5×5` on 3×3×3; scale consistently if you change cell size).

**Phonon mesh:** start with `32 32 32` on the supercell reciprocal cell;
converge \(\Delta F^{\mathrm{vib}}\) vs mesh (e.g. 16³ → 24³ → 32³ → 48³).

**Phonon bands:** `templates/bands.conf` — Γ–X–M–Γ–R, `BAND_POINTS=51`,
supercell reciprocal basis (`DIM = 1 1 1`). Keep `PRIMITIVE_AXES` as identity
so the input cell is not re-primitivized (P1 defects / already-2×2×2 cell).

**Metis launcher (conceptually, per job):**

```bash
source /opt/intel/oneapi/setvars.sh
export OMP_NUM_THREADS=1
nice -n 19 mpirun -np 8 -genv OMP_NUM_THREADS 1 /prog/bin/vasp_std
```

The batch driver additionally pins each concurrent job to a disjoint core
block via `I_MPI_PIN_PROCESSOR_LIST`.

---

## 9. Sanity checks

1. **Host:** `hostname` contains `metis`; step 0 prints `TARGET: Metis only (not Leto)`.
2. **POTCAR present** for `nodef`, `cVac`, `2G` (see §4 / `docs/POTCAR.md`); not tracked by git.
3. **Atom counts:** nodef 64, cVac 63 (32 Ti + 31 C), 2G 63 (31 Ti + 32 C).
4. **Factor:** always `63/32`, never `63/64` alone without the factor 2.
5. **Units:** phonopy free energy is kJ/mol·supercell → divide by 96.485 for eV;
   \(S\) and \(C_V\) in J K⁻¹ mol⁻¹ (also reported in eV/K in the tables).
6. **Sign of ZPE correction:** previous runs gave \(\Delta E_{\mathrm{ZPE}}\sim -0.07\) eV
   (small vs ~5 eV electronic term) — order of magnitude check.
7. **Thermodynamic identity:** \(\Delta F \approx \Delta U - T\Delta S\) (vib pieces).
8. **Same POTCAR / ENCUT / lattice** for all three structures.
9. Imaginary modes on defects: if present, try tighter force convergence,
   larger displacement amplitude test (0.01 vs 0.015 Å), or confirm 2G geometry.
10. **phonopy on PATH:** `bash run_workflow.sh --only 0` should print a
   phonopy path (and `phonopy-init` on v4), not an error.
11. **Core budget:** at most ~56 cores in use
   (`MAX_JOBS × NPROC`; check with `bash scripts/run_local_parallel.sh --status`).
12. **Bands:** `nodef` (192 modes), `cVac`/`2G` (189); Schottky band plot uses
    sorted + interpolated combo — may show negative \(\omega_{\mathrm{S}}\).

---

## 10. Relation to the papers (what this adds)

| paper | what they report | this workflow |
|-------|------------------|---------------|
| PRB L060103 | 2G is ground-state Me vacancy; reconstruction −3.5 eV | uses 2G POSCAR |
| Acta Mat. | \(E^{\mathrm{f}}_{\mathrm{Schottky}}\) static DFT, interaction maps | same static formula + **harmonic \(F_{\mathrm{vib}}(T)\)** |

The papers do **not** include phonon free-energy corrections; this workflow
adds the harmonic vibrational piece needed for finite-\(T\) Schottky free energy.

### 10.1 How to cite (BibTeX)

Please cite the two background articles **and** this software repository when
using the pipeline or publishing numbers obtained with it.

| cite key | what |
|----------|------|
| `smirnova2024` | 2G reconstructed metal vacancy (PRB) |
| `nourazar2026` | Schottky configuration / formation energies (Acta Materialia) |
| `nourazar2026phono` | this GitHub workflow / code |

Full file: **[`CITATION.bib`](CITATION.bib)**. GitHub metadata: **[`CITATION.cff`](CITATION.cff)**.

```bibtex
@article{smirnova2024,
  author  = {Smirnova, Ekaterina and Nourazar, Mehdi and Korzhavyi, Pavel A.},
  title   = {Internal structure of metal vacancies in cubic carbides},
  journal = {Physical Review B},
  volume  = {109},
  number  = {6},
  pages   = {L060103},
  year    = {2024},
  doi     = {10.1103/PhysRevB.109.L060103},
  url     = {https://doi.org/10.1103/PhysRevB.109.L060103}
}

@article{nourazar2026,
  author  = {Nourazar, Mehdi and Korzhavyi, Pavel Alexeevich},
  title   = {Configuration of {Schottky} defects in transition metal carbides},
  journal = {Acta Materialia},
  volume  = {317},
  pages   = {122538},
  year    = {2026},
  doi     = {10.1016/j.actamat.2026.122538},
  url     = {https://doi.org/10.1016/j.actamat.2026.122538}
}

@software{nourazar2026phono,
  author  = {Nourazar, Mehdi},
  title   = {{phono-tic-schottky}: Schottky formation free energy from phonopy
             and {VASP} for {TiC}},
  year    = {2026},
  url     = {https://github.com/mehDN/phono-tic-schottky},
  note    = {Harmonic phonon free-energy corrections for the TiC Schottky pair}
}
```

Plain-text:

- E. Smirnova, M. Nourazar, and P. A. Korzhavyi, Phys. Rev. B **109**, L060103 (2024).  
  https://doi.org/10.1103/PhysRevB.109.L060103
- M. Nourazar and P. A. Korzhavyi, Acta Mater. **317**, 122538 (2026).  
  https://doi.org/10.1016/j.actamat.2026.122538
- M. Nourazar, *phono-tic-schottky* (2026),  
  https://github.com/mehDN/phono-tic-schottky

---

## 11. Quick start (Metis)

```bash
# ON METIS — do not use Leto
ssh metis
cd /slask/mehdin/dynamics/phono

# optional permanent PATH fix for pip --user installs
export PATH="$HOME/.local/bin:$PATH"

# install licensed PAW POTCARs (not in git) — see docs/POTCAR.md
# cat $VASP_PP_PATH/potpaw_PBE/{Ti,C}/POTCAR > nodef/POTCAR
# cp -a nodef/POTCAR cVac/POTCAR 2G/POTCAR

# prerequisite check (phonopy + host=metis + POTCAR + 7×8≤56 plan)
bash run_workflow.sh --only 0

# full production run (prompts before local VASP on Metis)
bash run_workflow.sh

# non-interactive: Metis parallel pool, ≤56 cores (refuses Leto)
bash run_workflow.sh --auto-submit

# after all VASP force jobs have finished (if you stopped earlier)
bash run_workflow.sh --from 4
# → FORCE_SETS, thermal_properties.yaml, Schottky F/S/Cv + PDFs,
#   bands (nodef/cVac/2G) + bands_schottky.pdf

# thermal + Schottky + bands only (FORCE_SETS already present)
bash run_workflow.sh --thermal-only

# rebuild tables/plots/bands only
bash run_workflow.sh --schottky-only
bash run_workflow.sh --plot-only

# formula check only, using old phono_222 thermals (no new VASP)
bash run_workflow.sh --demo
```

Example static TOTEN values used in the demo come from `phono_222` OUTCARs
and **must be recomputed** with `templates/INCAR.static` for production.
