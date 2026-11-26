#!/bin/bash
# Tarea B.2 - hibrido MPI x OpenMP con 24 nucleos fijos. KPAR = N_MPI, NCORE=1 (forzado por OpenMP).
# 7 combinaciones x REPS = 21 jobs.  Uso: bash slurm/submit_B2_hibrido.sh
cd "$(dirname "$0")/.." && source slurm/config.sh
for r in $(seq 1 "$REPS"); do
  for c in "24 1" "12 2" "8 3" "6 4" "4 6" "2 12" "1 24"; do
    read -r M T <<< "$c"
    PARTE=B2 REP=$r KPAR=$M NCORE=1 \
    sbatch --job-name=B2_${M}x${T}_r$r --partition=phys_general --reservation=halzate_10 -w granado-compute-17 \
           --ntasks=$M --cpus-per-task=$T --time=$(( 15 + T1_MIN )) slurm/run_vasp.slurm
  done
done
