#!/usr/bin/env python3
"""Tareas B.1 (escalamiento debil) y B.2 (hibrido MPI x OpenMP con 24 CPUs).

Uso:  python analisis/hibrido_debil.py
Salidas: datos/tabla_hibrido.csv, datos/tabla_debil.csv, analisis/figuras/{hibrido,debil}.{pdf,png}

B.1: 1 proceso MPI por nucleo fisico (-c2), 16 k-points por proceso -> eje = nucleos = procesos.
B.2: la configuracion 1x24 es identica a A.2 con p = 24, asi que se toma de ahi.
Memoria: 'maxmem_kb' es lo que reporta VASP (proceso 0); la total se estima x numero de procesos.
"""
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "analisis" / "figuras"


def tiempos(df, parte):
    d = df[(df.parte == parte) & (df.convergido == 1)].copy()
    d["t"] = d.elapsed_s.fillna(d.t_wall_s)
    d["mem_MB"] = d.maxmem_kb / 1024
    return d


def hibrido(df):
    d = pd.concat([tiempos(df, "B2"),
                   tiempos(df, "A2").query("p == 24")])      # 1x24 = A.2 con p = 24
    if d.empty:
        print("B.2: sin corridas todavia")
        return
    g = (d.groupby(["nmpi", "nomp"])
           .agg(t_media=("t", "mean"), t_std=("t", "std"), n=("t", "count"),
                mem_MB_rank0=("mem_MB", "max"), n_scf=("n_scf", "mean"))
           .reset_index().sort_values("nmpi", ascending=False))
    g["mem_total_estimada_MB"] = g.mem_MB_rank0 * g.nmpi
    g["config"] = g.nmpi.astype(str) + "×" + g.nomp.astype(str)
    g.round(2).to_csv(ROOT / "datos" / "tabla_hibrido.csv", index=False)
    print(g.round(2).to_string(index=False))
    best = g.loc[g.t_media.idxmin()]
    print(f"Optimo: {best.config} con t = {best.t_media:.1f} s")
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.bar(g.config, g.t_media, yerr=g.t_std, capsize=3, color="C0")
    ax.set_xlabel("N_MPI × N_OMP (24 CPUs de Slurm = 12 núcleos físicos)")
    ax.set_ylabel("tiempo de pared (s)")
    ax.set_title("Paralelismo híbrido")
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(FIG / f"hibrido.{ext}", dpi=200)
    plt.close(fig)


def debil(df):
    d = tiempos(df, "B1")
    if d.empty:
        print("B.1: sin corridas todavia")
        return
    d["n"] = d.nmpi                                         # nucleos fisicos = procesos
    g = (d.groupby("n").agg(t_media=("t", "mean"), t_std=("t", "std"), reps=("t", "count"),
                            nkpts=("nkpts", "max"), mem_MB_rank0=("mem_MB", "max"))
           .reset_index())
    g["Ew"] = g.loc[g.n == 1, "t_media"].item() / g.t_media
    g["mem_total_estimada_MB"] = g.mem_MB_rank0 * g.n
    g.round(3).to_csv(ROOT / "datos" / "tabla_debil.csv", index=False)
    print(g.round(3).to_string(index=False))
    fig, ax = plt.subplots(figsize=(5.5, 4))
    ax.errorbar(g.n, g.Ew, yerr=g.Ew * g.t_std.fillna(0) / g.t_media, fmt="o-", capsize=3)
    ax.axhline(1, color="k", ls="--", lw=1)
    ax.set_xlabel("núcleos físicos n  (k-points = 16·n, 1 proceso por núcleo)")
    ax.set_ylabel("eficiencia débil  E_w = t(1)/t(n)")
    ax.set_xticks(list(g.n))
    ax.set_ylim(0, 1.15)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(FIG / f"debil.{ext}", dpi=200)
    plt.close(fig)


if __name__ == "__main__":
    FIG.mkdir(parents=True, exist_ok=True)
    data = pd.read_csv(ROOT / "datos" / "tiempos.csv")
    debil(data)
    hibrido(data)
