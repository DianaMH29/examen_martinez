#!/bin/bash
# Tarea B.1 - escalamiento debil por k-points, 1 proceso MPI por NUCLEO FISICO (-c2, 1 hilo)
# para que el hyperthreading no se mezcle con el costo de comunicacion.
# ISYM=-1 (sin simetria): numero de k-points exactamente N1*N2 = 16*n, con KPAR=n,
# asi cada proceso tiene siempre 16 k-points (trabajo por proceso constante).
#   n=1: 4x4   n=2: 4x8   n=4: 8x8   n=8: 8x16     (n = nucleos fisicos; se facturan 2n CPUs)
# 4 valores x REPS = 12 jobs.  Uso: bash slurm/submit_B1_debil.sh

cd "$(dirname "$0")/.." && source slurm/config.sh
declare -A MALLA=( [1]=4x4x1 [2]=4x8x1 [4]=8x8x1 [8]=8x16x1 )
for r in $(seq 1 "$REPS"); do
  for n in 1 2 4 8; do
    PARTE=B1 REP=$r KPAR=$n NCORE=1 OMP_THREADS=1 KMESH=${MALLA[$n]} INCAR_SET="ISYM=-1" \
    sbatch --job-name=B1_n$(printf %02d $n)_r$r \
           --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 \
           --ntasks=$n --cpus-per-task=2 --mem=30000M --time=$(( T1_MIN + 30 )) slurm/run_vasp.slurm
  done
done
