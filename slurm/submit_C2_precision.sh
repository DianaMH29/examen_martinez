#!/bin/bash
# Tarea C.2 - precision vs costo, todo con 8 procesos MPI (KPAR=8):
#   serie ENCUT con la malla base fija, y serie de malla k con ENCUT base fijo.
#   Las referencias "exactas" son el ENCUT y la malla mas altos.
# Uso: bash slurm/submit_C2_precision.sh

cd "$(dirname "$0")/.." && source slurm/config.sh
for E in 300 350 400 450 500 600 700 800 900; do
  PARTE=C2E REP=1 KPAR=8 NCORE=1 INCAR_SET="ENCUT=$E" \
  sbatch --job-name=C2_E$E --partition=phys_general --ntasks=8 --time=$(( 20 + T1_MIN )) slurm/run_vasp.slurm
done
for K in 6 9 12 15 18 21 24 30; do
  PARTE=C2K REP=1 KPAR=8 NCORE=1 KMESH=${K}x${K}x1 \
  sbatch --job-name=C2_k$K --partition=phys_general --ntasks=8 --time=$(( 20 + 2*T1_MIN )) slurm/run_vasp.slurm
done
