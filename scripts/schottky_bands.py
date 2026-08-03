#!/usr/bin/env python3
"""
Schottky combination of phonon band structures.

Same atom-balance formula as for free energy / entropy / Cv:

  ω_S(q, i) = ω_2G(q, i) + ω_cVac(q, i) - ((2N-1)/N) * ω_nodef(q, i)
            = ω_2G + ω_cVac - 1.96875 * ω_nodef

with N = 32.  Mode counts differ (nodef: 3×64 = 192, defects: 3×63 = 189);
DOF balance: 189 + 189 = 1.96875 × 192 = 378.

At each q-point, frequencies are sorted ascending and nodef's spectrum is
linearly interpolated in band-index fraction onto the defect band count
before applying the combination.

Writes (under --results-dir, default results/):
  bands_schottky.yaml
  bands_schottky.pdf
  bands_schotcky.pdf   (alias for the common typo)

Usage:
  python3.13 scripts/schottky_bands.py
  python3.13 scripts/schottky_bands.py --results-dir results
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

# Reuse loader / plot helpers from plot_bands
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from plot_bands import (  # noqa: E402
    _pretty_label,
    _segment_x_and_boundaries,
    find_band_yaml,
    load_band_yaml,
    plot_single,
)

N_SITES = 32
FACTOR = (2 * N_SITES - 1) / N_SITES  # 63/32 = 1.96875


def _sorted_freqs(f_q: np.ndarray) -> np.ndarray:
    """f_q: (nband,) → sorted ascending."""
    return np.sort(np.asarray(f_q, dtype=float))


def _interp_to_n(freqs_sorted: np.ndarray, n_out: int) -> np.ndarray:
    """Interpolate a sorted spectrum onto n_out band indices (fractional rank)."""
    f = np.asarray(freqs_sorted, dtype=float)
    n_in = f.size
    if n_in == n_out:
        return f.copy()
    if n_in == 1:
        return np.full(n_out, f[0], dtype=float)
    x_in = np.linspace(0.0, 1.0, n_in)
    x_out = np.linspace(0.0, 1.0, n_out)
    return np.interp(x_out, x_in, f)


def schottky_bands(nodef: dict, cvac: dict, twog: dict, factor: float = FACTOR) -> dict:
    """Apply Schottky combination segment-wise / q-wise."""
    nseg = len(nodef["distances"])
    if not (len(cvac["distances"]) == nseg == len(twog["distances"])):
        raise ValueError(
            f"segment count mismatch: nodef={len(nodef['distances'])} "
            f"cVac={len(cvac['distances'])} 2G={len(twog['distances'])}"
        )

    distances: list[np.ndarray] = []
    frequencies: list[np.ndarray] = []

    for iseg in range(nseg):
        d_n = np.asarray(nodef["distances"][iseg], dtype=float)
        d_c = np.asarray(cvac["distances"][iseg], dtype=float)
        d_g = np.asarray(twog["distances"][iseg], dtype=float)
        if not (len(d_n) == len(d_c) == len(d_g)):
            raise ValueError(
                f"segment {iseg}: nq mismatch nodef={len(d_n)} cVac={len(d_c)} 2G={len(d_g)}"
            )
        # Use 2G distances as reference (identical path by construction)
        if not np.allclose(d_n, d_g, atol=1e-6) or not np.allclose(d_c, d_g, atol=1e-6):
            # still OK if cumulative scale matches; warn via print
            print(
                f"  note: segment {iseg} distances differ slightly "
                f"(Δmax nodef={np.max(np.abs(d_n-d_g)):.3e}, "
                f"cVac={np.max(np.abs(d_c-d_g)):.3e})",
                flush=True,
            )

        f_n = np.asarray(nodef["frequencies"][iseg], dtype=float)  # (nq, nb_n)
        f_c = np.asarray(cvac["frequencies"][iseg], dtype=float)
        f_g = np.asarray(twog["frequencies"][iseg], dtype=float)
        nq = f_g.shape[0]
        nb_out = min(f_c.shape[1], f_g.shape[1])  # 189

        f_s = np.zeros((nq, nb_out), dtype=float)
        for iq in range(nq):
            sn = _sorted_freqs(f_n[iq])
            sc = _sorted_freqs(f_c[iq])
            sg = _sorted_freqs(f_g[iq])
            sn_i = _interp_to_n(sn, nb_out)
            # trim defects to nb_out if needed
            sc = sc[:nb_out] if sc.size >= nb_out else _interp_to_n(sc, nb_out)
            sg = sg[:nb_out] if sg.size >= nb_out else _interp_to_n(sg, nb_out)
            f_s[iq] = sg + sc - factor * sn_i

        distances.append(d_g.copy())
        frequencies.append(f_s)

    labels = twog.get("labels") or cvac.get("labels") or nodef.get("labels") or []
    return {
        "distances": distances,
        "frequencies": frequencies,
        "labels": labels,
        "segment_nq": [len(d) for d in distances],
        "factor": factor,
        "nband": frequencies[0].shape[1] if frequencies else 0,
    }


def write_schottky_yaml(band: dict, path: Path, factor: float) -> None:
    """Write a phonopy-like bands yaml for the Schottky combination."""
    lines: list[str] = []
    lines.append("# Schottky phonon bands: ω_S = ω_2G + ω_cVac - factor * ω_nodef")
    lines.append(f"# factor = (2N-1)/N = {factor:.12f}  (N=32)")
    lines.append("# Frequencies sorted at each q; nodef spectrum interpolated to defect nband.")
    lines.append(f"nqpoint: {sum(band['segment_nq'])}")
    lines.append(f"npath: {len(band['segment_nq'])}")
    lines.append("segment_nqpoint:")
    for nq in band["segment_nq"]:
        lines.append(f"- {nq}")
    lines.append(f"nband: {band['nband']}")
    lines.append("labels:")
    labs = band.get("labels") or []
    # emit as pairs if we have boundary labels
    if len(labs) >= 2:
        for i in range(len(labs) - 1):
            lines.append(f"- [ '{labs[i]}', '{labs[i+1]}' ]")
    lines.append("phonon:")
    for iseg, (dseg, fseg) in enumerate(zip(band["distances"], band["frequencies"])):
        for iq in range(len(dseg)):
            lines.append(f"- q-position: [ 0.0, 0.0, 0.0 ]  # segment {iseg} point {iq}")
            lines.append(f"  distance: {float(dseg[iq]):.10f}")
            lines.append("  band:")
            for ib, freq in enumerate(fseg[iq]):
                lines.append(f"  - # {ib+1}")
                lines.append(f"    frequency: {float(freq):.10f}")
    path.write_text("\n".join(lines) + "\n")


def plot_schottky(band: dict, out: Path, factor: float) -> None:
    fig, ax = plt.subplots(figsize=(6.2, 4.4))
    x_segs, boundaries = _segment_x_and_boundaries(band["distances"])
    for x, f in zip(x_segs, band["frequencies"]):
        f = np.asarray(f, dtype=float)
        for ib in range(f.shape[1]):
            ax.plot(x, f[:, ib], color="#1f77b4", lw=0.55, alpha=0.85)

    ax.axhline(0.0, color="0.2", lw=0.7, ls="--")
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
    ax.set_ylabel(r"$\omega_{\mathrm{Schottky}}$ (THz)")
    ax.set_title(
        r"Schottky phonon bands: "
        r"$\omega_{2\mathrm{G}}+\omega_{\mathrm{cVac}}-"
        + f"{factor:.5f}"
        + r"\,\omega_{\mathrm{nodef}}$"
    )
    ax.tick_params(direction="in", top=True, right=True)
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--nodef", type=Path, default=None, help="nodef dir or bands.yaml")
    p.add_argument("--cvac", type=Path, default=None, help="cVac dir or bands.yaml")
    p.add_argument("--twog", type=Path, default=None, help="2G dir or bands.yaml")
    p.add_argument("--results-dir", type=Path, default=None)
    p.add_argument("--factor", type=float, default=FACTOR)
    p.add_argument("--fmin", type=float, default=None)
    p.add_argument("--fmax", type=float, default=None)
    args = p.parse_args(argv)

    root = Path(__file__).resolve().parent.parent
    results = args.results_dir if args.results_dir is not None else root / "results"
    results.mkdir(parents=True, exist_ok=True)

    def resolve_yaml(arg: Path | None, default_dir: str) -> Path:
        if arg is None:
            return find_band_yaml(root / default_dir)
        arg = arg.resolve()
        if arg.is_dir():
            return find_band_yaml(arg)
        if arg.is_file():
            return arg
        raise FileNotFoundError(arg)

    path_n = resolve_yaml(args.nodef, "nodef")
    path_c = resolve_yaml(args.cvac, "cVac")
    path_g = resolve_yaml(args.twog, "2G")

    print(f"nodef: {path_n}", flush=True)
    print(f"cVac:  {path_c}", flush=True)
    print(f"2G:    {path_g}", flush=True)
    print(f"factor (2N-1)/N = {args.factor:.12f}", flush=True)

    nodef = load_band_yaml(path_n)
    cvac = load_band_yaml(path_c)
    twog = load_band_yaml(path_g)

    print(
        f"nband: nodef={nodef['frequencies'][0].shape[1]}  "
        f"cVac={cvac['frequencies'][0].shape[1]}  "
        f"2G={twog['frequencies'][0].shape[1]}",
        flush=True,
    )

    band = schottky_bands(nodef, cvac, twog, factor=args.factor)
    print(f"Schottky nband={band['nband']}  nq={sum(band['segment_nq'])}", flush=True)

    # Stats
    all_f = np.concatenate([f.ravel() for f in band["frequencies"]])
    print(
        f"ω_S range: [{all_f.min():.4f}, {all_f.max():.4f}] THz  "
        f"mean={all_f.mean():.4f}  (includes possible negative combo values)",
        flush=True,
    )

    out_yaml = results / "bands_schottky.yaml"
    out_pdf = results / "bands_schottky.pdf"
    out_pdf_typo = results / "bands_schotcky.pdf"  # requested spelling variant

    write_schottky_yaml(band, out_yaml, args.factor)
    print(f"Wrote {out_yaml}", flush=True)

    plt.rcParams.update(
        {
            "font.size": 11,
            "axes.labelsize": 12,
            "axes.titlesize": 11,
            "figure.dpi": 150,
            "savefig.dpi": 150,
            "pdf.fonttype": 42,
        }
    )
    plot_schottky(band, out_pdf, args.factor)
    if args.fmin is not None or args.fmax is not None:
        # replot with limits via plot_single-like path
        fig_path = out_pdf
        # simple re-open: plot again with ylim by calling plot and set
        fig, ax = plt.subplots(figsize=(6.2, 4.4))
        x_segs, boundaries = _segment_x_and_boundaries(band["distances"])
        for x, f in zip(x_segs, band["frequencies"]):
            f = np.asarray(f, dtype=float)
            for ib in range(f.shape[1]):
                ax.plot(x, f[:, ib], color="#1f77b4", lw=0.55, alpha=0.85)
        ax.axhline(0.0, color="0.2", lw=0.7, ls="--")
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
        ax.set_ylim(args.fmin, args.fmax)
        ax.set_ylabel(r"$\omega_{\mathrm{Schottky}}$ (THz)")
        ax.set_title("Schottky phonon bands")
        fig.tight_layout()
        fig.savefig(fig_path, bbox_inches="tight")
        plt.close(fig)

    shutil.copy2(out_pdf, out_pdf_typo)
    print(f"Wrote {out_pdf}", flush=True)
    print(f"Wrote {out_pdf_typo}  (alias)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
