#!/usr/bin/env python3
"""
Schottky defect free energy, entropy, and heat capacity from phonopy
thermal_properties.yaml files.

Two-supercell form (N = 32 metal or carbon sites in the 2x2x2 cell):

  X_Schottky(T) = X_2G(T) + X_cVac(T) - ((2N-1)/N) * X_nodef(T)
                = X_2G(T) + X_cVac(T) - 1.96875 * X_nodef(T)

where X is free_energy, energy, entropy, or heat_capacity from phonopy
(per supercell).

Total formation free energy (optional static DFT):

  F_f(T) = E_DFT_Schottky + dF_vib(T)

  E_DFT_Schottky = E_2G + E_cVac - 1.96875 * E_nodef   (eV, static TOTEN)

Phonopy units (per supercell):
  free_energy, energy : kJ/mol
  entropy, heat_capacity : J/K/mol

Outputs (default under results/):
  schottky_free_energy.dat
  schottky_entropy.dat
  schottky_heat_capacity.dat
  schottky.dat   (combined table, backward compatible)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# kJ/mol -> eV (per supercell as given by phonopy)
KJMOL_TO_EV = 1.0 / 96.485336459006
# J/K/mol -> eV/K
JKMOL_TO_EVK = KJMOL_TO_EV / 1000.0
# N sites per sublattice in 2x2x2 TiC
N_SITES = 32
FACTOR = (2 * N_SITES - 1) / N_SITES  # 63/32 = 1.96875


def parse_thermal_yaml(path: Path) -> dict:
    """Minimal parser for phonopy thermal_properties.yaml (no PyYAML required)."""
    text = path.read_text()
    out: dict = {
        "zero_point_energy": None,
        "natom": None,
        "points": [],  # list of dicts
    }
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("natom:"):
            out["natom"] = int(line.split(":", 1)[1].strip())
        elif line.startswith("zero_point_energy:"):
            out["zero_point_energy"] = float(line.split(":", 1)[1].strip())
        elif line.startswith("- temperature:"):
            if current:
                out["points"].append(current)
            current = {
                "temperature": float(line.split(":", 1)[1].strip()),
            }
        elif current is not None and ":" in line:
            key, val = line.split(":", 1)
            key = key.strip()
            if key in ("free_energy", "entropy", "heat_capacity", "energy"):
                current[key] = float(val.strip())
    if current:
        out["points"].append(current)
    if out["zero_point_energy"] is None:
        raise ValueError(f"no zero_point_energy in {path}")
    if not out["points"]:
        raise ValueError(f"no thermal_properties points in {path}")
    return out


def align_temperatures(a, b, c):
    """Return common temperature grid (intersection)."""
    ta = {p["temperature"] for p in a["points"]}
    tb = {p["temperature"] for p in b["points"]}
    tc = {p["temperature"] for p in c["points"]}
    common = sorted(ta & tb & tc)
    if not common:
        raise ValueError("no common temperatures among the three yaml files")
    ma = {p["temperature"]: p for p in a["points"]}
    mb = {p["temperature"]: p for p in b["points"]}
    mc = {p["temperature"]: p for p in c["points"]}
    return common, ma, mb, mc


def combo(x_nodef: float, x_cvac: float, x_2g: float, factor: float) -> float:
    """Schottky linear combination for any extensive phonon quantity."""
    return x_2g + x_cvac - factor * x_nodef


def write_table(path: Path, header_lines: list[str], rows: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as fh:
        for h in header_lines:
            fh.write(h if h.endswith("\n") else h + "\n")
        for r in rows:
            fh.write(r if r.endswith("\n") else r + "\n")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--nodef", type=Path, required=True, help="nodef thermal_properties.yaml")
    p.add_argument("--cvac", type=Path, required=True, help="cVac thermal_properties.yaml")
    p.add_argument("--twog", type=Path, required=True, help="2G thermal_properties.yaml")
    p.add_argument("--edft-nodef", type=float, default=None, help="static TOTEN nodef (eV)")
    p.add_argument("--edft-cvac", type=float, default=None, help="static TOTEN cVac (eV)")
    p.add_argument("--edft-2g", type=float, default=None, help="static TOTEN 2G (eV)")
    p.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="directory for separate F, S, Cv files (default: parent of --out)",
    )
    p.add_argument(
        "--out",
        type=Path,
        default=Path("results/schottky.dat"),
        help="combined table path (default: results/schottky.dat)",
    )
    p.add_argument(
        "--prefix",
        type=str,
        default="schottky",
        help="filename prefix for separate outputs (default: schottky)",
    )
    p.add_argument("--factor", type=float, default=FACTOR, help=f"atom-balance factor (default {FACTOR})")
    args = p.parse_args(argv)

    nodef = parse_thermal_yaml(args.nodef)
    cvac = parse_thermal_yaml(args.cvac)
    twog = parse_thermal_yaml(args.twog)

    print(f"natom: nodef={nodef['natom']}  cVac={cvac['natom']}  2G={twog['natom']}")
    print(f"factor (2N-1)/N = {args.factor:.12f}")

    # ZPE-only (kJ/mol and eV)
    zpe_kj = combo(
        nodef["zero_point_energy"],
        cvac["zero_point_energy"],
        twog["zero_point_energy"],
        args.factor,
    )
    zpe_ev = zpe_kj * KJMOL_TO_EV
    print(f"dE_ZPE = {zpe_kj:.6f} kJ/mol = {zpe_ev:.6f} eV")

    e_dft = None
    if None not in (args.edft_nodef, args.edft_cvac, args.edft_2g):
        e_dft = combo(args.edft_nodef, args.edft_cvac, args.edft_2g, args.factor)
        print(f"E_DFT_Schottky = {e_dft:.6f} eV")
        print(f"F_Schottky(0 K) = {e_dft + zpe_ev:.6f} eV  (DFT + ZPE)")
    else:
        print("Note: pass --edft-nodef/--edft-cvac/--edft-2g to include static DFT term.")

    temps, ma, mb, mc = align_temperatures(nodef, cvac, twog)

    out_dir = args.out_dir if args.out_dir is not None else args.out.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = args.prefix

    path_f = out_dir / f"{prefix}_free_energy.dat"
    path_s = out_dir / f"{prefix}_entropy.dat"
    path_cv = out_dir / f"{prefix}_heat_capacity.dat"
    path_combined = args.out

    rows_f: list[str] = []
    rows_s: list[str] = []
    rows_cv: list[str] = []
    rows_all: list[str] = []

    for T in temps:
        pa, pb, pc = ma[T], mb[T], mc[T]

        # Free energy / internal energy (kJ/mol -> eV)
        dF = combo(pa["free_energy"], pb["free_energy"], pc["free_energy"], args.factor) * KJMOL_TO_EV
        dU = combo(pa["energy"], pb["energy"], pc["energy"], args.factor) * KJMOL_TO_EV

        # Entropy / Cv (J/K/mol -> eV/K and keep J/K/mol)
        dS_j = combo(pa["entropy"], pb["entropy"], pc["entropy"], args.factor)
        dCv_j = combo(pa["heat_capacity"], pb["heat_capacity"], pc["heat_capacity"], args.factor)
        dS_ev = dS_j * JKMOL_TO_EVK
        dCv_ev = dCv_j * JKMOL_TO_EVK

        if e_dft is None:
            e_col = float("nan")
            Ftot = dF
            Utot = dU
        else:
            e_col = e_dft
            Ftot = e_dft + dF
            Utot = e_dft + dU

        rows_f.append(
            f"{T:12.4f}  {dF:14.8f}  {e_col:14.8f}  {Ftot:14.8f}  {dU:14.8f}  {Utot:14.8f}"
        )
        rows_s.append(
            f"{T:12.4f}  {dS_ev:14.8e}  {dS_j:14.8f}"
        )
        rows_cv.append(
            f"{T:12.4f}  {dCv_ev:14.8e}  {dCv_j:14.8f}"
        )
        rows_all.append(
            f"{T:12.4f}  {dF:14.8f}  {dU:14.8f}  {e_col:14.8f}  {Ftot:14.8f}  "
            f"{Utot:14.8f}  {dS_ev:14.8e}  {dS_j:14.8f}  {dCv_ev:14.8e}  {dCv_j:14.8f}"
        )

    factor_tag = f"factor={args.factor:.12f}"
    formula = "X_S = X_2G + X_cVac - factor * X_nodef"

    write_table(
        path_f,
        [
            f"# Schottky free energy from phonopy; {factor_tag}",
            f"# {formula}",
            f"# dE_ZPE = {zpe_ev:.8f} eV",
            f"# E_DFT_Schottky = {e_dft if e_dft is not None else float('nan'):.8f} eV",
            "# T[K]  dF_vib[eV]  E_DFT[eV]  F_Schottky[eV]  dU_vib[eV]  U_Schottky[eV]",
        ],
        rows_f,
    )
    write_table(
        path_s,
        [
            f"# Schottky formation entropy from phonopy; {factor_tag}",
            f"# {formula}  (X = entropy)",
            "# T[K]  dS_vib[eV/K]  dS_vib[J/K/mol]",
        ],
        rows_s,
    )
    write_table(
        path_cv,
        [
            f"# Schottky formation heat capacity (Cv) from phonopy; {factor_tag}",
            f"# {formula}  (X = heat_capacity)",
            "# T[K]  dCv_vib[eV/K]  dCv_vib[J/K/mol]",
        ],
        rows_cv,
    )
    write_table(
        path_combined,
        [
            f"# Schottky from phonopy; {factor_tag}",
            f"# {formula}",
            "# T[K]  dF_vib[eV]  dU_vib[eV]  E_DFT[eV]  F_Schottky[eV]  U_Schottky[eV]  "
            "dS[eV/K]  dS[J/K/mol]  dCv[eV/K]  dCv[J/K/mol]",
        ],
        rows_all,
    )

    print(f"Wrote {path_f}  ({len(temps)} temperatures)")
    print(f"Wrote {path_s}")
    print(f"Wrote {path_cv}")
    print(f"Wrote {path_combined}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
