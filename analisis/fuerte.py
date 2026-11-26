#!/usr/bin/env python3
"""Tarea A.3: escalamiento fuerte. Genera DOS figuras:

1) fuerte_S_E      -> eje = CPUs de Slurm (la definicion del examen): A1 (MPI) y A2 (OpenMP).
2) fuerte_nucleos  -> eje = nucleos FISICOS. En Granado 1 CPU de Slurm = 1 hilo de hyperthreading,
                      asi que con p >= 2 CPUs hay p/2 nucleos con 2 procesos/hilos cada uno.
                      Aqui se compara A1 y A2 (2 por nucleo) con A1c (1 proceso por nucleo, sin HT).
   Con p = 1 el proceso tiene el nucleo completo para el solo, por eso nucleos = max(1, p/2).

Uso:  python analisis/fuerte.py      (requiere datos/tiempos.csv de extraer.py)
Salidas: analisis/figuras/fuerte_S_E.{pdf,png}, analisis/figuras/fuerte_nucleos.{pdf,png},
         datos/resumen_fuerte.csv

Ajuste de Amdahl: 1/S = f + (1-f)/x  =>  (1/S - 1/x) = f (1 - 1/x)  (lineal en f, minimos cuadrados).
Karp-Flatt: f_e(x) = (1/S - 1/x)/(1 - 1/x). Si crece con x hay sobrecosto (comunicacion, memoria);
si DECRECE, el eje no mide recursos equivalentes (ej. hyperthreading en x = 2).
"""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "analisis" / "figuras"
ESTILO = {  # parte: (etiqueta, color, marcador)
    "A1": ("MPI, KPAR = p", "C0", "o"),
    "A2": ("OpenMP, 1 proceso", "C3", "s"),
    "A1c": ("MPI, 1 proceso por núcleo físico", "C1", "D"),
}


def tiempos(df, parte, eje):
    """Media y desviacion por punto. eje: 'cpus' o 'nucleos'."""
    d = df[(df.parte == parte) & (df.convergido == 1)].copy()
    if d.empty:
        return None
    d["t"] = d.elapsed_s.fillna(d.t_wall_s)
    if parte == "A1c":                      # -c2: 1 proceso = 1 nucleo; se facturan 2 CPUs por proceso
        d["x"] = d.nmpi if eje == "nucleos" else 2 * d.nmpi
        ref = d[d.nmpi == 1]
    elif eje == "cpus":
        d["x"] = d.p
        ref = d[d.p == 1]
    else:
        # Referencia: p = 1 (1 proceso con el nucleo completo). Puntos: p >= 2 -> p/2 nucleos con
        # 2 procesos/hilos cada uno. Asi el punto x = 1 es p = 2 y muestra la ganancia del HT.
        ref = d[d.p == 1]
        d = d[d.p >= 2].copy()
        d["x"] = d.p // 2
    if ref.empty:
        return None
    t1, s1 = ref.t.mean(), (ref.t.std() if len(ref) > 1 else 0.0)
    g = d.groupby("x").t.agg(["mean", "std", "count"]).reset_index()
    g["S"] = t1 / g["mean"]
    g["S_err"] = g.S * np.sqrt((s1 / t1) ** 2 + (g["std"].fillna(0) / g["mean"]) ** 2)
    g["E"] = g.S / g.x
    g["E_err"] = g.S_err / g.x
    x, y = 1 - 1 / g.x, 1 / g.S - 1 / g.x
    m = g.x > 1
    f = float((x[m] * y[m]).sum() / (x[m] ** 2).sum()) if m.any() else np.nan
    g["karp_flatt"] = np.where(m, y / x.where(m), np.nan)
    # Amdahl + sobrecosto lineal: t(x)/t1 = f + (1-f)/x + k (x-1)
    #   => t/t1 - 1/x = f (1 - 1/x) + k (x - 1), lineal en (f, k)
    fk = (np.nan, np.nan)
    if m.sum() >= 2:
        A = np.column_stack([x[m], (g.x - 1)[m]])
        fk = tuple(np.linalg.lstsq(A, y[m], rcond=None)[0])
    g.insert(0, "eje", eje)
    g.insert(0, "modo", parte)
    return g, f, fk


def figura(df, eje, partes, nombre, titulo, xlab, nk=None):
    fig, (axS, axE) = plt.subplots(1, 2, figsize=(10, 4.2))
    xmax = 24 if eje == "cpus" else 12
    xx = np.linspace(1, xmax, 200)
    axS.plot(xx, xx, "k--", lw=1, label="ideal")
    axE.axhline(1, color="k", ls="--", lw=1)
    axE.axhline(0.5, color="gray", ls=":", lw=1)
    if nk:  # limite por reparto de k-points: el grupo mas cargado tiene ceil(Nk/x) k-points
        xk = np.arange(1, xmax + 1)
        sb = nk / np.ceil(nk / xk)
        axS.step(xk, sb, where="mid", color="gray", lw=1, label=f"límite por k-points (Nk = {nk})")
        axE.step(xk, sb / xk, where="mid", color="gray", lw=1)
    tablas = []
    for parte in partes:
        r = tiempos(df, parte, eje)
        if r is None:
            continue
        g, f, (f2, k) = r
        tablas.append(g)
        et, c, mk = ESTILO[parte]
        axS.errorbar(g.x, g.S, yerr=g.S_err, fmt=mk, color=c, capsize=3, label=et)
        if np.isfinite(f) and f < 1:
            axS.plot(xx, 1 / (f + (1 - f) / xx), "-", color=c, alpha=0.5, label=f"Amdahl f = {f:.3f}")
        elif np.isfinite(f2):   # S < 1: Amdahl no puede describirlo (f > 1); se usa el modelo con sobrecosto
            axS.plot(xx, 1 / (f2 + (1 - f2) / xx + k * (xx - 1)), "--", color=c, alpha=0.6,
                     label=f"Amdahl + sobrecosto: f = {f2:.2f}, k = {k:.3f}")
        axE.errorbar(g.x, g.E, yerr=g.E_err, fmt=mk + "-", color=c, capsize=3, label=et)
        print(f"[{eje}] {et}: Amdahl f = {f:.4f} | Amdahl+sobrecosto f = {f2:.4f}, k = {k:.4f}")
    ticks = [1, 2, 4, 8, 12, 16, 24] if eje == "cpus" else [1, 2, 4, 6, 8, 12]
    for ax, et in [(axS, "Aceleración S"), (axE, "Eficiencia E = S / x")]:
        ax.set_xlabel(xlab)
        ax.set_ylabel(et)
        ax.set_xticks(ticks)
        ax.grid(alpha=0.3)
    axE.set_ylim(0, 1.15)
    axS.legend(fontsize=7)
    axE.legend(fontsize=7)
    fig.suptitle(titulo)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(FIG / f"{nombre}.{ext}", dpi=200)
    plt.close(fig)
    return tablas


def main():
    FIG.mkdir(parents=True, exist_ok=True)
    df = pd.read_csv(ROOT / "datos" / "tiempos.csv")
    nk = df.loc[df.parte == "A1", "nkpts"].dropna()
    nk = int(nk.iloc[0]) if len(nk) else None
    t1 = figura(df, "cpus", ["A1", "A2"], "fuerte_S_E",
                "Escalamiento fuerte — Cr$_2$SeTeO AFM (eje: CPUs de Slurm)", "CPUs de Slurm p", nk)
    t2 = figura(df, "nucleos", ["A1", "A2", "A1c"], "fuerte_nucleos",
                "Escalamiento fuerte por núcleos físicos (A1, A2: 2 por núcleo; A1c: 1 por núcleo)",
                "núcleos físicos", nk)
    tabla = pd.concat(t1 + t2)
    tabla.round(4).to_csv(ROOT / "datos" / "resumen_fuerte.csv", index=False)
    print(tabla.round(3).to_string(index=False))


if __name__ == "__main__":
    main()
