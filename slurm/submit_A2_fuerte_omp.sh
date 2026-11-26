#!/bin/bash
# NOTA: corrido con el modulo original vasp/6.3.0-gnu9-openmp; las corridas quedaron en runs_modulo_viejo/.
# La version valida de A.2 esta en submit_final.sh (modulo V2 + OPENBLAS_NUM_THREADS=1).
# Tarea A.2 - escalamiento fuerte, solo OpenMP: 1 proceso con p hilos (VASP fuerza NCORE=1 con OpenMP).
# 21 jobs.  Uso: bash slurm/submit_A2_fuerte_omp.sh
cd "$(dirname "$0")/.." && source slurm/config.sh
for r in $(seq 1 "$REPS"); do
  for p in 1 2 4 8 12 16 24; do
    PARTE=A2 REP=$r KPAR=1 NCORE=1 \
    sbatch --job-name=A2_p$(printf %02d $p)_r$r --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 \
           --ntasks=1 --cpus-per-task=$p --time=$(tlim $p 6) slurm/run_vasp.slurm
  done
done
