#!/usr/bin/env python3
"""Recorre runs/*/ (meta.txt + OUTCAR + OSZICAR) y escribe datos/tiempos.csv.

Uso:  python analisis/extraer.py
Una fila por corrida. Tiempo principal: 'elapsed_s' (linea 'Elapsed time' del OUTCAR);
't_wall_s' es el tiempo medido por el job alrededor de srun (incluye arranque de MPI).
"""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "runs"
SALIDA = ROOT / "datos" / "tiempos.csv"

PATRONES = {  # se toma la ULTIMA coincidencia en el OUTCAR
    "elapsed_s": r"Elapsed time \(sec\):\s*([\d.]+)",
    "maxmem_kb": r"Maximum memory used \(kb\):\s*([\d.]+)",
    "nkpts": r"NKPTS\s*=\s*(\d+)",
    "nbands": r"NBANDS\s*=\s*(\d+)",
    "nplwv": r"NPLWV\s*=\s*(\d+)",
    "toten_eV": r"TOTEN\s*=\s*(-?\d+\.\d+)",
    "e_sigma0_eV": r"energy\(sigma->0\)\s*=\s*(-?\d+\.\d+)",
}
CAMPOS = ["tag", "parte", "rep", "nmpi", "nomp", "omp_threads", "p", "kpar", "ncore", "kmesh", "incar_set",
          "partition", "modulo", "nodes", "jobid", "t_wall_s", "elapsed_s", "n_scf", "t_scf_medio_s",
          "maxmem_kb", "nkpts", "nbands", "nplwv", "toten_eV", "e_sigma0_eV", "mag",
          "convergido", "carpeta"]


def leer_meta(f):
    d = {}
    for linea in f.read_text().splitlines():
        if "=" in linea:
            k, v = linea.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def leer_corrida(carpeta):
    fila = leer_meta(carpeta / "meta.txt")
    fila["p"] = int(fila["nmpi"]) * int(fila["nomp"])
    fila["carpeta"] = carpeta.name
    outcar = carpeta / "OUTCAR"
    texto = outcar.read_text(errors="ignore") if outcar.exists() else ""
    for campo, patron in PATRONES.items():
        m = re.findall(patron, texto)
        fila[campo] = m[-1] if m else ""
    loops = re.findall(r"LOOP:\s+cpu time\s+[\d.]+:\s+real time\s+([\d.]+)", texto)
    fila["t_scf_medio_s"] = f"{sum(map(float, loops)) / len(loops):.3f}" if loops else ""
    fila["convergido"] = int("EDIFF is reached" in texto)
    osz = carpeta / "OSZICAR"
    if osz.exists():
        lineas = osz.read_text().splitlines()
        fila["n_scf"] = sum(1 for l in lineas if re.match(r"^(DAV|RMM|CG|SDA):", l))
        mags = [l.split("mag=")[-1].strip() for l in lineas if "mag=" in l]
        fila["mag"] = mags[-1] if mags else ""
    return fila


def main():
    filas = []
    for meta in sorted(RUNS.glob("*/meta.txt")):
        try:
            filas.append(leer_corrida(meta.parent))
        except Exception as e:  # una corrida rota no debe tumbar todo el analisis
            print(f"[aviso] {meta.parent.name}: {e}")
    SALIDA.parent.mkdir(exist_ok=True)
    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CAMPOS, extrasaction="ignore")
        w.writeheader()
        w.writerows(filas)
    malas = [f["tag"] for f in filas if not f["elapsed_s"] or not f["convergido"]]
    print(f"{len(filas)} corridas -> {SALIDA.relative_to(ROOT)}")
    if malas:
        print("Revisar (sin terminar o sin converger):", ", ".join(malas))


if __name__ == "__main__":
    main()
