#!/bin/bash
# Fase final con el modulo corregido vasp/6.3.0-gnu9-openmpV2 (OpenBLAS recompilado)
# y OPENBLAS_NUM_THREADS=1: A.2, B.2 y C.2 en UNA sola cadena (cada job espera al anterior).
# Orden por repeticion: si se acaba el tiempo, al menos queda una repeticion completa de todo.
#   rep 1: A.2 (7) + B.2 (6) + C.2 (9)     rep 2: A.2 + B.2     rep 3: A.2 + B.2    -> 48 jobs
# B.2 1x24 no se corre: es identico a A.2 con p=24.
# NCORE=1 siempre (con OpenMP, VASP lo recomienda); KPAR = numero de procesos MPI.
# Uso:  bash slurm/submit_final.sh          (REPS=2 bash slurm/submit_final.sh para solo 2)

cd "$(dirname "$0")/.." && source slurm/config.sh
export VASP_MODULE=vasp/6.3.0-gnu9-openmpV2
COMUN="--partition=phys_fast --reservation=halzate_10 -w granado-compute-17"
LIM=$(( T1_MIN + 20 ))        # holgado: con OpenMP la aceleracion es baja

enviar () {   # enviar NOMBRE NTASKS CPUS_POR_TAREA MINUTOS   (PARTE, KPAR, etc. por entorno)
  ULTIMO=$(sbatch --parsable $(dep) $COMUN --job-name="$1" --ntasks="$2" \
                  --cpus-per-task="$3" --time="$4" slurm/run_vasp.slurm)
  echo "$1 -> $ULTIMO"
}

for r in $(seq 1 "$REPS"); do
  # A.2: 1 proceso con p hilos OpenMP
  for p in 1 2 4 8 12 16 24; do
    PARTE=A2 REP=$r KPAR=1 NCORE=1 enviar A2v2_p$(printf %02d $p)_r$r 1 $p $LIM
  done
  # B.2: N_MPI x N_OMP = 24 CPUs
  for c in "24 1" "12 2" "8 3" "6 4" "4 6" "2 12"; do
    read -r M T <<< "$c"
    PARTE=B2 REP=$r KPAR=$M NCORE=1 enviar B2v2_${M}x${T}_r$r $M $T $LIM
  done
  # C.2 (solo una vez): 4 procesos MPI, 1 por nucleo fisico
  if [[ $r == 1 ]]; then
    for E in 300 400 500 700; do
      PARTE=C2E REP=1 KPAR=4 NCORE=1 OMP_THREADS=1 INCAR_SET="ENCUT=$E" \
        enviar C2_E$E 4 2 $LIM
    done
    for K in 6 9 12 18 24; do
      PARTE=C2K REP=1 KPAR=4 NCORE=1 OMP_THREADS=1 KMESH=${K}x${K}x1 \
        enviar C2_k$K 4 2 $(( T1_MIN + 30 ))
    done
  fi
done
