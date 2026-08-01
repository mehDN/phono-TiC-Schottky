# Obtaining POTCAR files (VASP PAW potentials)

This repository **does not ship POTCAR files**. VASP projector-augmented-wave
(PAW) potentials are **licensed commercial content** from the VASP group. Only
licensed VASP users may download and use them.

## What this workflow needs

| item | value |
|------|--------|
| Functional family | **PBE** (`PAW_PBE`, `LEXCH = PE`) |
| Elements (POSCAR order) | **Ti**, then **C** |
| Recommended datasets | `PAW_PBE Ti 08Apr2002`, `PAW_PBE C 08Apr2002` (standard, not `_sv` / `_pv` unless you deliberately change the study) |
| Where files live in this tree | `nodef/POTCAR`, `cVac/POTCAR`, `2G/POTCAR` (same file for all three) |
| After `02_prepare_vasp_jobs.sh` | copies of that POTCAR into every `disp_*/` and `static/` |

POSCAR species line is `Ti C`, so the concatenated POTCAR **must** list Ti first,
then C (one “End of Dataset” block per species).

## Who can get them

1. Hold a valid **VASP license** (university / group license is fine).
2. Log in to the VASP portal and download the official PAW potsets, **or**
3. Use the potset already installed on your HPC / local machine (common paths
   below).

Official site: [https://www.vasp.at](https://www.vasp.at)  
Portal / downloads (license required): [https://www.vasp.at/](https://www.vasp.at/)
→ user area / potpaw downloads as provided by your license agreement.

## Build the concatenated POTCAR

### Option A — from the official potpaw_PBE tree

After you unpack the VASP potsets (names vary slightly by release):

```bash
# Example layout after unpacking VASP potpaw_PBE:
#   $VASP_PP_PATH/potpaw_PBE/Ti/POTCAR
#   $VASP_PP_PATH/potpaw_PBE/C/POTCAR

export VASP_PP_PATH=/path/to/vasp/potentials   # your site

# Ti then C — must match POSCAR element order
cat \
  "${VASP_PP_PATH}/potpaw_PBE/Ti/POTCAR" \
  "${VASP_PP_PATH}/potpaw_PBE/C/POTCAR" \
  > nodef/POTCAR

# Same file for all three structures (same species order)
cp -a nodef/POTCAR cVac/POTCAR
cp -a nodef/POTCAR 2G/POTCAR
```

Verify:

```bash
grep TITEL nodef/POTCAR
# expect:
#   TITEL  = PAW_PBE Ti 08Apr2002
#   TITEL  = PAW_PBE C 08Apr2002
```

### Option B — Metis / local site pot directory

On many MSE machines the potsets live under a shared path (ask your admin if
missing). Examples to search:

```bash
# illustrative only — path may differ on your system
ls /prog/vasp/potpaw_PBE/Ti/POTCAR 2>/dev/null
ls /opt/vasp/potpaw_PBE/Ti/POTCAR 2>/dev/null
find /prog /opt -path '*potpaw_PBE/Ti/POTCAR' 2>/dev/null | head
```

Then use the same `cat` as in Option A with that directory as `VASP_PP_PATH`.

### Option C — copy from another licensed project of yours

If you already have a valid Ti+C PBE POTCAR for a previous TiC study:

```bash
cp /path/to/your/licensed/TiC/POTCAR nodef/POTCAR
cp -a nodef/POTCAR cVac/POTCAR 2G/POTCAR
```

Ensure species order is still **Ti then C**.

## Propagate into job directories

Staging scripts **copy** the structure-level POTCAR into each job folder:

```bash
# After nodef/POTCAR, cVac/POTCAR, 2G/POTCAR exist:
bash scripts/05_static_energies.sh      # */static/POTCAR
bash scripts/02_prepare_vasp_jobs.sh    # disp_*/POTCAR + r.sh
```

If jobs were staged earlier without POTCARs (fresh clone), re-run those two
scripts (or re-copy manually):

```bash
for s in nodef cVac 2G; do
  for d in "$s"/static "$s"/disp_*; do
    [[ -d "$d" ]] || continue
    cp -a "$s/POTCAR" "$d/POTCAR"
  done
done
```

## Consistency rules

- Use the **same** POTCAR (and ENCUT, lattice, KPOINTS family) for `nodef`,
  `cVac`, and `2G`. Mixing GW / LDA / different Ti variants invalidates the
  Schottky energy difference.
- Do **not** commit POTCAR to git (see root `.gitignore`).
- Do **not** share potsets outside your licensed group.

## Checklist for new clones

```bash
git clone <this-repo>
cd phono-tic-schottky   # or your clone path

# 1) Install POTCARs (this file)
# 2) On Metis only:
ssh metis
cd /path/to/clone
export PATH="$HOME/.local/bin:$PATH"
bash run_workflow.sh --only 0    # fails if POTCAR missing
```
