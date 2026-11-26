#!/bin/bash
# Serie de CONTROL para A.1: 1 proceso MPI por NUCLEO FISICO.
# En Granado 1 CPU de Slurm = 1 hilo de hyperthreading; con --cpus-per-task=2 cada proceso recibe
# un nucleo completo (sus 2 hilos) y corre con 1 solo hilo (OMP_THREADS=1).
# Se factura 2 CPUs por proceso, asi que el maximo es 12 procesos (24 CPUs).
# Comparada con A.1 (--cpus-per-task=1) separa el paralelismo real del efecto del hyperthreading.
# 5 valores x REPS = 15 jobs.  Uso: bash slurm/submit_A1c_nucleos.sh
cd "$(dirname "$0")/.." && source slurm/config.sh
for r in $(seq 1 "$REPS"); do
  for p in 1 2 4 6 12; do
    PARTE=A1c REP=$r KPAR=$p NCORE=1 OMP_THREADS=1 \
    sbatch --job-name=A1c_n$(printf %02d $p)_r$r --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 \
           --ntasks=$p --cpus-per-task=2 --time=$(tlim $p) slurm/run_vasp.slurm
  done
done
