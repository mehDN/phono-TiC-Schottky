#!/usr/bin/env python3
"""
Schottky defect free energy from phonopy thermal_properties.yaml files.

Two-supercell form (N = 32 metal or carbon sites in the 2x2x2 cell):

  X_Schottky(T) = X_2G(T) + X_cVac(T) - ((2N-1)/N) * X_nodef(T)
                = X_2G(T) + X_cVac(T) - 1.96875 * X_nodef(T)

where X is free_energy or energy from phonopy (kJ/mol per supercell).

Total formation free energy:

  F_f(T) = E_DFT_Schottky + dF_vib(T)

  E_DFT_Schottky = E_2G + E_cVac - 1.96875 * E_nodef   (eV, static TOTEN)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# kJ/mol -> eV (per formula / per supercell as given by phonopy)
KJMOL_TO_EV = 1.0 / 96.485336459006
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


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--nodef", type=Path, required=True, help="nodef thermal_properties.yaml")
    p.add_argument("--cvac", type=Path, required=True, help="cVac thermal_properties.yaml")
    p.add_argument("--twog", type=Path, required=True, help="2G thermal_properties.yaml")
    p.add_argument("--edft-nodef", type=float, default=None, help="static TOTEN nodef (eV)")
    p.add_argument("--edft-cvac", type=float, default=None, help="static TOTEN cVac (eV)")
    p.add_argument("--edft-2g", type=float, default=None, help="static TOTEN 2G (eV)")
    p.add_argument("--out", type=Path, default=Path("results/schottky.dat"))
    p.add_argument("--factor", type=float, default=FACTOR, help=f"atom-balance factor (default {FACTOR})")
    args = p.parse_args(argv)

    nodef = parse_thermal_yaml(args.nodef)
    cvac = parse_thermal_yaml(args.cvac)
    twog = parse_thermal_yaml(args.twog)

    print(f"natom: nodef={nodef['natom']}  cVac={cvac['natom']}  2G={twog['natom']}")
    print(f"factor (2N-1)/N = {args.factor:.12f}")

    # ZPE-only (kJ/mol and eV)
    zpe_kj = (
        twog["zero_point_energy"]
        + cvac["zero_point_energy"]
        - args.factor * nodef["zero_point_energy"]
    )
    zpe_ev = zpe_kj * KJMOL_TO_EV
    print(f"dE_ZPE = {zpe_kj:.6f} kJ/mol = {zpe_ev:.6f} eV")

    e_dft = None
    if None not in (args.edft_nodef, args.edft_cvac, args.edft_2g):
        e_dft = args.edft_2g + args.edft_cvac - args.factor * args.edft_nodef
        print(f"E_DFT_Schottky = {e_dft:.6f} eV")
        print(f"F_Schottky(0 K) = {e_dft + zpe_ev:.6f} eV  (DFT + ZPE)")
    else:
        print("Note: pass --edft-nodef/--edft-cvac/--edft-2g to include static DFT term.")

    temps, ma, mb, mc = align_temperatures(nodef, cvac, twog)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w") as fh:
        fh.write(f"# Schottky from phonopy; factor={(args.factor):.12f}\n")
        fh.write("# T[K]  dF_vib[eV]  dU_vib[eV]  E_DFT[eV]  F_Schottky[eV]  U_Schottky[eV]\n")
        for T in temps:
            Fa = ma[T]["free_energy"]
            Fb = mb[T]["free_energy"]
            Fc = mc[T]["free_energy"]
            Ua = ma[T]["energy"]
            Ub = mb[T]["energy"]
            Uc = mc[T]["energy"]
            dF = (Fc + Fb - args.factor * Fa) * KJMOL_TO_EV
            dU = (Uc + Ub - args.factor * Ua) * KJMOL_TO_EV
            if e_dft is None:
                e_col = float("nan")
                Ftot = dF
                Utot = dU
            else:
                e_col = e_dft
                Ftot = e_dft + dF
                Utot = e_dft + dU
            fh.write(
                f"{T:12.4f}  {dF:14.8f}  {dU:14.8f}  {e_col:14.8f}  {Ftot:14.8f}  {Utot:14.8f}\n"
            )

    print(f"Wrote {args.out}  ({len(temps)} temperatures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
