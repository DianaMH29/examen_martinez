#!/usr/bin/env python3
"""Tareas C.1 (reproducibilidad vs p) y C.2 (error vs costo).

Uso:  python analisis/precision.py
C.1: compara la energia (energy(sigma->0)) de las corridas A1/A2 con p = 1, 4, 16, 24 respecto a la
     media de p = 1, en eV y en unidades de eps_mach:  n_eps = |dE| / (|E| * eps_mach).
     Ojo con el piso de resolucion: el OUTCAR imprime 8 decimales (1e-8 eV), asi que una
     diferencia menor a ~1e-8/(|E| eps) eps_mach es invisible.
C.2: error |E - E_ref| por atomo vs tiempo, para las series de ENCUT (C2E) y de malla k (C2K).
"""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
EPS = {"doble": 2.0 ** -52, "simple": 2.0 ** -23}
N_ATOMOS = 5


def c1(df):
    filas = []
    for parte in ("A1", "A2"):
        d = df[(df.parte == parte) & df.p.isin([1, 4, 16, 24])]
        if d.empty or 1 not in set(d.p):
            continue
        e_ref = d.loc[d.p == 1, "e_sigma0_eV"].mean()
        piso = 1e-8 / (abs(e_ref) * EPS["doble"])
        for _, r in d.sort_values(["p", "rep"]).iterrows():
            de = r.e_sigma0_eV - e_ref
            filas.append({"modo": parte, "p": r.p, "rep": r.rep, "E_eV": r.e_sigma0_eV,
                          "dE_eV": de, "n_eps_mach": abs(de) / (abs(e_ref) * EPS["doble"]),
                          "n_scf": r.n_scf})
        print(f"{parte}: piso de resolucion del OUTCAR = {piso:.2e} eps_mach")
    if filas:
        t = pd.DataFrame(filas)
        t.to_csv(ROOT / "datos" / "tabla_reproducibilidad.csv", index=False)
        print(t.to_string(index=False, float_format=lambda v: f"{v:.3e}"))


def c2(df):
    """Error vs tiempo. Referencia = el valor MAS ALTO del parametro (ENCUT o malla), no el mas lento.
    'rendimiento' = -dlog10(error)/dlog10(t) entre puntos consecutivos: cuantas decadas de error
    se ganan por cada decada de tiempo. Cuando cae por debajo de ~1, subir la precision ya no compensa."""
    fig, ax = plt.subplots(figsize=(6.2, 4.3))
    for parte, nombre, col in [("C2E", "ENCUT (eV), malla 12×12×1", "C0"),
                               ("C2K", "malla k (N×N×1), ENCUT 400 eV", "C3")]:
        d = df[(df.parte == parte) & (df.convergido == 1)].copy()
        if len(d) < 2:
            continue
        d["t"] = d.elapsed_s.fillna(d.t_wall_s)
        if parte == "C2E":
            d["param"] = d.incar_set.str.extract(r"ENCUT=(\d+)", expand=False).astype(float)
        else:
            d["param"] = d.kmesh.astype(str).str.split().str[0].astype(float)
        d = d.sort_values("param")
        ref = d.iloc[-1]
        d = d.iloc[:-1].copy()
        d["err_meV_atomo"] = 1000 * (d.e_sigma0_eV - ref.e_sigma0_eV).abs() / N_ATOMOS
        lt, le = np.log10(d.t.values), np.log10(d.err_meV_atomo.clip(lower=1e-6).values)
        d["rendimiento"] = np.r_[np.nan, -(np.diff(le) / np.diff(lt))]
        ax.loglog(d.t, d.err_meV_atomo, "o-", color=col, label=f"{nombre}; ref = {int(ref.param)}")
        for x, y, s in zip(d.t, d.err_meV_atomo, d.param):
            ax.annotate(f"{int(s)}", (x, y), fontsize=7, xytext=(4, 3), textcoords="offset points")
        cols = [c for c in ["tag", "param", "t", "n_scf", "nkpts", "err_meV_atomo", "rendimiento"] if c in d]
        d[cols].round(5).to_csv(
            ROOT / "datos" / f"tabla_{parte}.csv", index=False)
        print(f"\n{nombre} (referencia {int(ref.param)}, t_ref = {ref.t:.0f} s)")
        print(d[["param", "t", "n_scf", "nkpts", "err_meV_atomo", "rendimiento"]].round(4).to_string(index=False))
    ax.axhline(1, color="gray", ls=":", lw=1, label="1 meV/átomo")
    ax.set_xlabel("tiempo de pared (s), 4 procesos MPI (1 por núcleo físico)")
    ax.set_ylabel("|E − E_ref| (meV/átomo)")
    ax.grid(alpha=0.3, which="both")
    ax.legend(fontsize=7)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(ROOT / "analisis" / "figuras" / f"precision_vs_costo.{ext}", dpi=200)


if __name__ == "__main__":
    (ROOT / "analisis" / "figuras").mkdir(exist_ok=True)
    data = pd.read_csv(ROOT / "datos" / "tiempos.csv")
    c1(data)
    c2(data)
