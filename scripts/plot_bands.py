#!/usr/bin/env python3
"""
Plot phonon band structures from bands.yaml / band.yaml to PDF.

Writes:
  <struct>/bands.pdf
  results/bands_<struct>.pdf
  results/bands.pdf          (all structures side-by-side)

Usage:
  python3.13 scripts/plot_bands.py
  python3.13 scripts/plot_bands.py --results-dir results
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

import numpy as np

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def find_band_yaml(struct_dir: Path) -> Path:
    for name in ("bands.yaml", "band.yaml"):
        p = struct_dir / name
        if p.is_file():
            return p
    raise FileNotFoundError(f"no bands.yaml/band.yaml in {struct_dir}")


def load_band_yaml(path: Path) -> dict:
    """Load phonopy band.yaml / bands.yaml via PyYAML."""
    try:
        import yaml
    except ImportError as exc:
        raise ImportError("PyYAML is required to plot bands (pip install pyyaml)") from exc

    with path.open() as fh:
        data = yaml.safe_load(fh)

    phonon = data["phonon"]
    segment_nq = data.get("segment_nqpoint")
    if segment_nq is None:
        # Infer breaks when distance resets to ~0 after first point
        segment_nq = []
        count = 0
        prev_d = None
        for pt in phonon:
            d = float(pt["distance"])
            if prev_d is not None and d + 1e-12 < prev_d and d < 1e-8 and count > 0:
                segment_nq.append(count)
                count = 0
            count += 1
            prev_d = d
        segment_nq.append(count)

    distances: list[np.ndarray] = []
    frequencies: list[np.ndarray] = []
    idx = 0
    for nq in segment_nq:
        seg = phonon[idx : idx + nq]
        idx += nq
        d = np.array([float(pt["distance"]) for pt in seg], dtype=float)
        f = np.array(
            [[float(b["frequency"]) for b in pt["band"]] for pt in seg],
            dtype=float,
        )
        distances.append(d)
        frequencies.append(f)

    # labels: list of [start, end] pairs → boundary labels
    raw_labels = data.get("labels") or []
    boundary_labels: list[str] = []
    if raw_labels and isinstance(raw_labels[0], (list, tuple)):
        boundary_labels.append(str(raw_labels[0][0]))
        for pair in raw_labels:
            boundary_labels.append(str(pair[1]))
    elif raw_labels:
        boundary_labels = [str(x) for x in raw_labels]

    return {
        "distances": distances,
        "frequencies": frequencies,
        "labels": boundary_labels,
        "segment_nq": list(segment_nq),
    }


def _pretty_label(lab: str) -> str:
    lab = lab.strip()
    replacements = {
        "G": r"$\Gamma$",
        "Gamma": r"$\Gamma$",
        r"$\Gamma$": r"$\Gamma$",
        r"$\\Gamma$": r"$\Gamma$",
    }
    return replacements.get(lab, lab)


def _segment_x_and_boundaries(distances: list[np.ndarray]):
    """Return list of x-arrays (cumulative) and boundary positions."""
    x_segments = []
    boundaries = [0.0]
    offset = 0.0
    for i, d in enumerate(distances):
        d = np.asarray(d, dtype=float)
        # If distance is already cumulative across segments, d[0] continues;
        # if each segment starts near 0, accumulate.
        if i == 0:
            x = d.copy()
        elif d[0] < 1e-12:
            x = d + offset
        elif d[0] + 1e-9 >= offset:
            x = d.copy()
        else:
            x = d + offset
        x_segments.append(x)
        offset = float(x[-1])
        boundaries.append(offset)
    return x_segments, boundaries


def plot_single(band: dict, out: Path, title: str, fmin=None, fmax=None) -> None:
    fig, ax = plt.subplots(figsize=(6.0, 4.2))
    x_segs, boundaries = _segment_x_and_boundaries(band["distances"])
    for x, f in zip(x_segs, band["frequencies"]):
        f = np.asarray(f, dtype=float)
        for ib in range(f.shape[1]):
            ax.plot(x, f[:, ib], color="#1f77b4", lw=0.75)

    ax.axhline(0.0, color="0.3", lw=0.5, ls=":")
    for b in boundaries[1:-1]:
        ax.axvline(b, color="k", lw=0.6)

    labels = band.get("labels") or []
    if labels:
        labs = [_pretty_label(l) for l in labels[: len(boundaries)]]
        if len(labs) < len(boundaries):
            labs += [""] * (len(boundaries) - len(labs))
        ax.set_xticks(boundaries)
        ax.set_xticklabels(labs)

    ax.set_xlim(boundaries[0], boundaries[-1])
    if fmin is not None or fmax is not None:
        ax.set_ylim(fmin, fmax)
    ax.set_ylabel("Frequency (THz)")
    ax.set_title(title)
    ax.tick_params(direction="in", top=True, right=True)
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def plot_combined(bands: list[tuple[str, dict]], out: Path, fmin=None, fmax=None) -> None:
    n = len(bands)
    fig, axes = plt.subplots(1, n, figsize=(4.6 * n, 4.0), sharey=True)
    if n == 1:
        axes = [axes]
    for ax, (name, band) in zip(axes, bands):
        x_segs, boundaries = _segment_x_and_boundaries(band["distances"])
        for x, f in zip(x_segs, band["frequencies"]):
            f = np.asarray(f, dtype=float)
            for ib in range(f.shape[1]):
                ax.plot(x, f[:, ib], color="#1f77b4", lw=0.65)
        ax.axhline(0.0, color="0.3", lw=0.5, ls=":")
        for b in boundaries[1:-1]:
            ax.axvline(b, color="k", lw=0.55)
        labels = band.get("labels") or []
        if labels:
            labs = [_pretty_label(l) for l in labels[: len(boundaries)]]
            if len(labs) < len(boundaries):
                labs += [""] * (len(boundaries) - len(labs))
            ax.set_xticks(boundaries)
            ax.set_xticklabels(labs, fontsize=9)
        ax.set_xlim(boundaries[0], boundaries[-1])
        if fmin is not None or fmax is not None:
            ax.set_ylim(fmin, fmax)
        ax.set_title(name)
        ax.tick_params(direction="in", top=True, right=True)
        if ax is axes[0]:
            ax.set_ylabel("Frequency (THz)")
    fig.suptitle("Phonon band structure", y=1.02)
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dirs", nargs="*", type=Path, help="structure dirs (default: nodef cVac 2G)")
    p.add_argument("--results-dir", type=Path, default=None)
    p.add_argument("--fmin", type=float, default=None)
    p.add_argument("--fmax", type=float, default=None)
    args = p.parse_args(argv)

    root = Path(__file__).resolve().parent.parent
    results = args.results_dir if args.results_dir is not None else root / "results"
    results.mkdir(parents=True, exist_ok=True)
    dirs = args.dirs if args.dirs else [root / s for s in ("nodef", "cVac", "2G")]

    plt.rcParams.update(
        {
            "font.size": 11,
            "axes.labelsize": 12,
            "axes.titlesize": 12,
            "figure.dpi": 150,
            "savefig.dpi": 150,
            "pdf.fonttype": 42,
        }
    )

    loaded: list[tuple[str, dict]] = []
    for d in dirs:
        d = d.resolve()
        if not d.is_dir():
            print(f"ERROR: not a directory: {d}", file=sys.stderr)
            return 1
        yml = find_band_yaml(d)
        print(f"[{d.name}] reading {yml.name}", flush=True)
        band = load_band_yaml(yml)
        loaded.append((d.name, band))

        out_local = d / "bands.pdf"
        plot_single(band, out_local, title=f"Phonon bands — {d.name}", fmin=args.fmin, fmax=args.fmax)
        dest = results / f"bands_{d.name}.pdf"
        shutil.copy2(out_local, dest)
        # Clear alias for perfect cell (nodef) and each structure
        alias = results / f"{d.name}_bands.pdf"
        shutil.copy2(out_local, alias)
        # also copy yaml into results
        shutil.copy2(yml, results / f"bands_{d.name}.yaml")
        conf = d / "bands.conf"
        if conf.is_file():
            shutil.copy2(conf, results / f"bands_{d.name}.conf")
        print(f"[{d.name}] Wrote {out_local} → {dest} (+ {alias.name})", flush=True)

        # Optional phonopy-bandplot style PDF
        try:
            import subprocess

            band_yaml = d / "band.yaml"
            if not band_yaml.is_file():
                shutil.copy2(yml, band_yaml)
            out_pb = results / f"bands_{d.name}_phonopy-bandplot.pdf"
            subprocess.run(
                ["phonopy-bandplot", str(band_yaml), "-o", str(out_pb), "-t", d.name],
                check=False,
                capture_output=True,
            )
        except Exception:
            pass

    out_all = results / "bands.pdf"
    plot_combined(loaded, out_all, fmin=args.fmin, fmax=args.fmax)
    print(f"Wrote {out_all}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
