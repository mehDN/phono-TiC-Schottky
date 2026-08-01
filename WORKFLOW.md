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
vibrational Helmholtz free energy \(F_{\mathrm{vib}}(T)\) (includes ZPE)
and the vibrational internal energy \(U_{\mathrm{vib}}(T)\):

\[
F_{\mathrm{vib}}(T)
  = \frac12\sum_{\mathbf{q}\nu}\hbar\omega_{\mathbf{q}\nu}
  + k_{\mathrm{B}}T\sum_{\mathbf{q}\nu}
    \ln\!\bigl[1-e^{-\hbar\omega_{\mathbf{q}\nu}/k_{\mathrm{B}}T}\bigr].
\]

At \(T=0\), \(F_{\mathrm{vib}} = U_{\mathrm{vib}} = E_{\mathrm{ZPE}}\).

Apply the **same atom-balance factor** to vibrational free energies:

\[
\boxed{
\Delta F^{\mathrm{vib}}_{\mathrm{Schottky}}(T)
  = F^{\mathrm{vib}}_{\mathrm{2G}}(T)
  + F^{\mathrm{vib}}_{\mathrm{cVac}}(T)
  - \frac{63}{32}\, F^{\mathrm{vib}}_{\mathrm{nodef}}(T)
}
\]

and likewise for \(\Delta U^{\mathrm{vib}}\) / \(\Delta E_{\mathrm{ZPE}}\).

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

Phonopy units: free energy in **kJ/mol of supercell**. Convert to eV with

\[
1\,\mathrm{kJ\,mol^{-1}} = 1/96.485336459\,\mathrm{eV} \approx 0.01036427\,\mathrm{eV}.
\]

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
├── run_workflow.sh             # *** main entry point (run everything) ***
├── templates/
│   ├── INCAR.static            # single-point total energy
│   ├── INCAR.forces            # finite-displacement forces (phonopy)
│   ├── KPOINTS                 # Gamma 3×3×3 for 2×2×2 supercell
│   ├── mesh.conf               # thermal properties mesh
│   ├── band.conf               # optional phonon bands
│   └── disp.conf               # create displacements
├── scripts/
│   ├── cluster_env.sh           # Metis defaults, host checks (not Leto)
│   ├── run_local_parallel.sh    # Metis core-capped parallel VASP pool
│   ├── submit_all_structures.sh # run all nodef/cVac/2G forces on Metis
│   ├── 01_create_displacements.sh
│   ├── 02_prepare_vasp_jobs.sh  # stages disp_*/ + Metis r.sh
│   ├── 03_collect_force_sets.sh
│   ├── 04_thermal_properties.sh
│   ├── 05_static_energies.sh
│   ├── count_vasp_progress.sh
│   ├── schottky_from_thermal.py
│   └── run_demo_from_phono222.sh
├── docs/
│   └── POTCAR.md                # how to obtain licensed PAW POTCARs
├── nodef/   POSCAR (64 atoms); add POTCAR yourself  (+ disp_*/ after step 3)
├── cVac/    POSCAR (63 atoms); add POTCAR yourself
├── 2G/      POSCAR (63 atoms); add POTCAR yourself
└── results/                    # Schottky tables; local_runs/*.log
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
| `bash run_workflow.sh --from 4` | Resume after VASP forces finished (FORCE_SETS → thermal → Schottky) |
| `bash run_workflow.sh --only 2` | Run a single step (0–6) |
| `bash run_workflow.sh --skip-static` | Skip staging static DFT (step 1) |
| `bash run_workflow.sh --demo` | Build Schottky table from existing `../phono_222` thermals (no VASP) |
| `bash scripts/submit_all_structures.sh` | Metis force pool only (all structures) |
| `bash scripts/run_local_parallel.sh --status` | Pending / done / live `vasp_std` count |

### 6.3 Pipeline steps (inside `run_workflow.sh`)

| step | action |
|------|--------|
| 0 | Prerequisites (POSCAR/POTCAR, phonopy, **host = Metis**, core plan) |
| 1 | Stage (and optionally run) static DFT → `*/static/` on Metis |
| 2 | Create finite displacements (`phonopy -d`) |
| 3 | Prepare `disp_*/` jobs; optionally run Metis pool and wait |
| 4 | Collect `FORCE_SETS` / write `FORCE_CONSTANTS` |
| 5 | Thermal properties → `*/thermal_properties.yaml` |
| 6 | Schottky table → `results/schottky.dat` |

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

### 6.5 PATH and finding phonopy

Phonopy is often installed with `pip install --user` so the CLI lands in
**`~/.local/bin`**, which is **not always on `PATH`**. That produces:

```text
[error] phonopy not on PATH (needed for steps 2, 4, 5)
```

**What the scripts do automatically**

1. Prepend `$HOME/.local/bin` to `PATH` at the start of `run_workflow.sh`
   and of steps `01`, `03`, `04`.
2. Resolve the binary in this order:
   - `phonopy` already on `PATH`
   - `$HOME/.local/bin/phonopy` if executable
   - `python3 -m phonopy` if the Python module imports
3. Export `PHONOPY_BIN` for child scripts when found.

On Metis a typical working install is:

```text
~/.local/bin/phonopy   (phonopy 2.20.0)
python3 -c "import phonopy"   # works
```

**Permanent shell fix (recommended once):**

```bash
# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Install / reinstall if missing:**

```bash
python3 -m pip install --user 'phonopy>=2.20'
which phonopy
phonopy -h | head
```

**Override the phonopy executable explicitly:**

```bash
export PHONOPY_BIN="$HOME/.local/bin/phonopy"
# or: export PHONOPY_BIN="python3 -m phonopy"
bash run_workflow.sh
```

### 6.6 Output of step 6

```text
results/schottky.dat
# T[K]  dF_vib[eV]  dU_vib[eV]  E_DFT[eV]  F_Schottky[eV]  U_Schottky[eV]
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

### Step 4 — build FORCE_SETS and FORCE_CONSTANTS

After all `vasprun.xml` exist:

```bash
bash scripts/03_collect_force_sets.sh
```

### Step 5 — thermal properties (incl. ZPE)

```bash
bash scripts/04_thermal_properties.sh
# phonopy -c POSCAR -t --dim="1 1 1" --mesh="32 32 32" --tmax=2000 --tstep=10
```

Near-zero acoustic frequencies at Γ (~10⁻³ THz) are OK; large imaginary
modes mean the structure is unstable or forces are bad.

### Step 6 — Schottky free energy

```bash
python3 scripts/schottky_from_thermal.py \
  --nodef nodef/thermal_properties.yaml \
  --cvac  cVac/thermal_properties.yaml \
  --twog  2G/thermal_properties.yaml \
  --edft-nodef  <TOTEN_eV> \
  --edft-cvac   <TOTEN_eV> \
  --edft-2g     <TOTEN_eV> \
  --out results/schottky.dat
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
5. **Units:** phonopy free energy is kJ/mol·supercell → divide by 96.485 for eV.
6. **Sign of ZPE correction:** previous runs gave \(\Delta E_{\mathrm{ZPE}}\sim -0.07\) eV
   (small vs ~5 eV electronic term) — order of magnitude check.
7. **Same POTCAR / ENCUT / lattice** for all three structures.
8. Imaginary modes on defects: if present, try tighter force convergence,
   larger displacement amplitude test (0.01 vs 0.015 Å), or confirm 2G geometry.
9. **phonopy on PATH:** `bash run_workflow.sh --only 0` should print a
   phonopy path (or `python3 -m phonopy`), not an error.
10. **Core budget:** at most ~56 cores in use
   (`MAX_JOBS × NPROC`; check with `bash scripts/run_local_parallel.sh --status`).

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

# formula check only, using old phono_222 thermals (no new VASP)
bash run_workflow.sh --demo
```

Example static TOTEN values used in the demo come from `phono_222` OUTCARs
and **must be recomputed** with `templates/INCAR.static` for production.
