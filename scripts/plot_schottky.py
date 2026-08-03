#!/usr/bin/env python3
"""
Plot Schottky free energy, entropy, and heat capacity vs temperature.

Reads results from schottky_from_thermal.py and writes PDFs under results/:

  schottky_free_energy.pdf
  schottky_entropy.pdf
  schottky_heat_capacity.pdf
  schottky_all.pdf          (three panels in one figure)

Usage:
  python3 scripts/plot_schottky.py
  python3 scripts/plot_schottky.py --results-dir results
  python3 scripts/plot_schottky.py --prefix schottky --tmax 2000
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

# Non-interactive backend before pyplot
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def load_cols(path: Path, ncol_min: int) -> np.ndarray:
    """Load numeric table, skipping comment lines."""
    if not path.is_file():
        raise FileNotFoundError(f"missing data file: {path}")
    data = np.loadtxt(path, comments="#")
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] < ncol_min:
        raise ValueError(f"{path}: expected ≥{ncol_min} columns, got {data.shape[1]}")
    return data


def style_axes(ax, xlabel: str = "Temperature (K)") -> None:
    ax.set_xlabel(xlabel)
    ax.grid(True, which="both", linestyle=":", linewidth=0.6, alpha=0.7)
    ax.tick_params(direction="in", top=True, right=True)


def plot_free_energy(T, F, dF, out: Path, title: str | None = None) -> None:
    fig, ax = plt.subplots(figsize=(5.5, 4.0))
    ax.plot(T, F, color="#1f77b4", lw=1.8, label=r"$F^{\mathrm{f}}_{\mathrm{Schottky}}(T)$")
    if dF is not None and np.any(np.isfinite(dF)):
        # Only show vib piece if it differs from total F (DFT present)
        if not np.allclose(F, dF, equal_nan=True):
            ax.plot(T, dF, color="#ff7f0e", lw=1.2, ls="--", label=r"$\Delta F_{\mathrm{vib}}(T)$")
    ax.set_ylabel(r"Free energy (eV)")
    style_axes(ax)
    ax.legend(frameon=False, loc="best")
    if title:
        ax.set_title(title)
    else:
        ax.set_title("Schottky formation free energy")
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def plot_entropy(T, S_j, out: Path, title: str | None = None) -> None:
    fig, ax = plt.subplots(figsize=(5.5, 4.0))
    ax.plot(T, S_j, color="#2ca02c", lw=1.8)
    ax.set_ylabel(r"$\Delta S_{\mathrm{vib}}$ (J K$^{-1}$ mol$^{-1}$)")
    style_axes(ax)
    ax.set_title(title or "Schottky formation entropy")
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def plot_heat_capacity(T, Cv_j, out: Path, title: str | None = None) -> None:
    fig, ax = plt.subplots(figsize=(5.5, 4.0))
    ax.plot(T, Cv_j, color="#d62728", lw=1.8)
    ax.set_ylabel(r"$\Delta C_{V,\mathrm{vib}}$ (J K$^{-1}$ mol$^{-1}$)")
    style_axes(ax)
    ax.set_title(title or "Schottky formation heat capacity")
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def plot_all(T, F, S_j, Cv_j, out: Path) -> None:
    fig, axes = plt.subplots(3, 1, figsize=(6.0, 8.5), sharex=True)

    axes[0].plot(T, F, color="#1f77b4", lw=1.8)
    axes[0].set_ylabel(r"$F^{\mathrm{f}}$ (eV)")
    axes[0].set_title("Schottky formation free energy, entropy, and heat capacity")
    style_axes(axes[0], xlabel="")

    axes[1].plot(T, S_j, color="#2ca02c", lw=1.8)
    axes[1].set_ylabel(r"$\Delta S$ (J K$^{-1}$ mol$^{-1}$)")
    style_axes(axes[1], xlabel="")

    axes[2].plot(T, Cv_j, color="#d62728", lw=1.8)
    axes[2].set_ylabel(r"$\Delta C_V$ (J K$^{-1}$ mol$^{-1}$)")
    style_axes(axes[2])

    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument(
        "--results-dir",
        type=Path,
        default=None,
        help="directory with schottky_*.dat (default: <repo>/results)",
    )
    p.add_argument("--prefix", type=str, default="schottky", help="filename prefix (default: schottky)")
    p.add_argument("--tmin", type=float, default=None, help="optional min T [K] to plot")
    p.add_argument("--tmax", type=float, default=None, help="optional max T [K] to plot")
    p.add_argument(
        "--dpi",
        type=int,
        default=150,
        help="PDF rasterization DPI for any embedded artists (default 150)",
    )
    args = p.parse_args(argv)

    root = Path(__file__).resolve().parent.parent
    results = args.results_dir if args.results_dir is not None else root / "results"
    results = results.resolve()
    prefix = args.prefix

    path_f = results / f"{prefix}_free_energy.dat"
    path_s = results / f"{prefix}_entropy.dat"
    path_cv = results / f"{prefix}_heat_capacity.dat"

    fdat = load_cols(path_f, 4)
    sdat = load_cols(path_s, 3)
    cvdat = load_cols(path_cv, 3)

    T = fdat[:, 0]
    dF = fdat[:, 1]
    F = fdat[:, 3]  # F_Schottky (includes E_DFT when available)
    # entropy: col1 eV/K, col2 J/K/mol
    S_j = sdat[:, 2]
    Cv_j = cvdat[:, 2]

    # Align lengths if needed (should match)
    n = min(len(T), len(S_j), len(Cv_j))
    T, dF, F, S_j, Cv_j = T[:n], dF[:n], F[:n], S_j[:n], Cv_j[:n]

    mask = np.ones(n, dtype=bool)
    if args.tmin is not None:
        mask &= T >= args.tmin
    if args.tmax is not None:
        mask &= T <= args.tmax
    T, dF, F, S_j, Cv_j = T[mask], dF[mask], F[mask], S_j[mask], Cv_j[mask]
    if T.size == 0:
        print("ERROR: no temperatures left after tmin/tmax filter", file=sys.stderr)
        return 1

    plt.rcParams.update(
        {
            "font.size": 11,
            "axes.labelsize": 12,
            "axes.titlesize": 12,
            "legend.fontsize": 10,
            "figure.dpi": args.dpi,
            "savefig.dpi": args.dpi,
            "pdf.fonttype": 42,  # editable text in PDF
        }
    )

    out_f = results / f"{prefix}_free_energy.pdf"
    out_s = results / f"{prefix}_entropy.pdf"
    out_cv = results / f"{prefix}_heat_capacity.pdf"
    out_all = results / f"{prefix}_all.pdf"

    plot_free_energy(T, F, dF, out_f)
    plot_entropy(T, S_j, out_s)
    plot_heat_capacity(T, Cv_j, out_cv)
    plot_all(T, F, S_j, Cv_j, out_all)

    print(f"Wrote {out_f}")
    print(f"Wrote {out_s}")
    print(f"Wrote {out_cv}")
    print(f"Wrote {out_all}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
