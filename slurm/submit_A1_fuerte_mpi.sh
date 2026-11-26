#!/bin/bash
# Tarea A.1 - escalamiento fuerte, solo MPI: p procesos, 1 hilo, KPAR=p (cada proceso con sus k-points), NCORE=1.
# 7 valores de p x REPS repeticiones = 21 jobs.  
# Uso: bash slurm/submit_A1_fuerte_mpi.sh

cd "$(dirname "$0")/.." && source slurm/config.sh
for r in $(seq 1 "$REPS"); do
  for p in 1 2 4 8 12 16 24; do
    PARTE=A1 REP=$r KPAR=$p NCORE=1 \
    sbatch --job-name=A1_p$(printf %02d $p)_r$r --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 \
           --ntasks=$p --cpus-per-task=1 --time=$(tlim $p) slurm/run_vasp.slurm
  done
done