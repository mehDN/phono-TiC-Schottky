#!/usr/bin/env python3
"""
Run phonopy thermal properties for a structure directory that already has
FORCE_SETS (or FORCE_CONSTANTS) and POSCAR.

Writes thermal_properties.yaml in the structure directory.

Phonopy v4 Python API (CLI mesh flags are brittle with phonopy_disp.yaml).
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path


def run_one(
    workdir: Path,
    mesh: tuple[int, int, int],
    tmin: float,
    tmax: float,
    tstep: float,
    write_fc: bool = False,
) -> Path:
    from phonopy import load

    workdir = workdir.resolve()
    poscar = workdir / "POSCAR"
    force_sets = workdir / "FORCE_SETS"
    force_constants = workdir / "FORCE_CONSTANTS"
    if not poscar.is_file():
        raise FileNotFoundError(f"missing {poscar}")
    if not force_sets.is_file() and not force_constants.is_file():
        raise FileNotFoundError(f"need FORCE_SETS or FORCE_CONSTANTS in {workdir}")

    t0 = time.time()
    kwargs = dict(
        supercell_matrix=[[1, 0, 0], [0, 1, 0], [0, 0, 1]],
        primitive_matrix="P",  # keep input cell (already 2x2x2 supercell / P1 defects)
        unitcell_filename=str(poscar),
        produce_fc=True,
    )
    if force_constants.is_file() and not force_sets.is_file():
        kwargs["force_constants_filename"] = str(force_constants)
    else:
        kwargs["force_sets_filename"] = str(force_sets)

    print(f"[{workdir.name}] loading phonopy ...", flush=True)
    ph = load(**kwargs)
    print(
        f"[{workdir.name}] loaded in {time.time()-t0:.1f}s  "
        f"natom={len(ph.unitcell)}  mesh={mesh[0]}x{mesh[1]}x{mesh[2]}",
        flush=True,
    )

    if write_fc:
        # Full force-constant matrix for faster re-runs / bands
        from phonopy.file_IO import write_FORCE_CONSTANTS

        fc_path = workdir / "FORCE_CONSTANTS"
        write_FORCE_CONSTANTS(ph.force_constants, filename=str(fc_path))
        print(f"[{workdir.name}] wrote {fc_path}", flush=True)

    ph.run_mesh(list(mesh), is_gamma_center=True)
    print(f"[{workdir.name}] mesh done in {time.time()-t0:.1f}s", flush=True)

    ph.run_thermal_properties(t_min=tmin, t_max=tmax, t_step=tstep)
    # write into workdir
    out = workdir / "thermal_properties.yaml"
    # API writes to CWD by default
    cwd = Path.cwd()
    try:
        import os

        os.chdir(workdir)
        ph.write_yaml_thermal_properties("thermal_properties.yaml")
    finally:
        os.chdir(cwd)

    if not out.is_file():
        raise RuntimeError(f"thermal_properties.yaml not written in {workdir}")

    # ZPE from thermal object
    tp = ph.thermal_properties
    temps = list(tp.temperatures)
    free = list(tp.free_energy)
    zpe = free[0] if temps and temps[0] == 0.0 else free[0]
    print(
        f"[{workdir.name}] thermal_properties.yaml  "
        f"nT={len(temps)}  F(Tmin)={zpe:.6f} kJ/mol  "
        f"elapsed={time.time()-t0:.1f}s",
        flush=True,
    )
    return out


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "dirs",
        nargs="*",
        type=Path,
        help="structure directories (default: nodef cVac 2G under repo root)",
    )
    p.add_argument("--mesh", type=int, nargs=3, default=[32, 32, 32], metavar=("NX", "NY", "NZ"))
    p.add_argument("--tmin", type=float, default=0.0)
    p.add_argument("--tmax", type=float, default=2000.0)
    p.add_argument("--tstep", type=float, default=10.0)
    p.add_argument("--write-fc", action="store_true", help="also write FORCE_CONSTANTS")
    p.add_argument(
        "--copy-to",
        type=Path,
        default=None,
        help="optional directory to copy thermal_properties_<name>.yaml into",
    )
    args = p.parse_args(argv)

    root = Path(__file__).resolve().parent.parent
    dirs = args.dirs if args.dirs else [root / s for s in ("nodef", "cVac", "2G")]
    mesh = (int(args.mesh[0]), int(args.mesh[1]), int(args.mesh[2]))

    for d in dirs:
        if not d.is_dir():
            print(f"ERROR: not a directory: {d}", file=sys.stderr)
            return 1
        out = run_one(d, mesh, args.tmin, args.tmax, args.tstep, write_fc=args.write_fc)
        if args.copy_to is not None:
            args.copy_to.mkdir(parents=True, exist_ok=True)
            dest = args.copy_to / f"thermal_properties_{d.name}.yaml"
            shutil.copy2(out, dest)
            print(f"[{d.name}] copied → {dest}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
