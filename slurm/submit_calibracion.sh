#!/bin/bash
# Tarea 0 - calibracion del caso base: tres candidatos en 1 nucleo.
# Se elige el que tarde entre 15 y 60 min
# Costo maximo: 3 x 1.5 h = 4.5 h-nucleo. 
# Sirve ademas como p=1 de la Parte A y como primeros puntos de la Tarea C.2.

# Uso:  bash slurm/submit_calibracion.sh

cd "$(dirname "$0")/.."
for cand in "400 12x12x1" "500 15x15x1" "600 18x18x1"; do
  read -r ENC K <<< "$cand"
  PARTE=CAL REP=1 KPAR=1 NCORE=1 KMESH=$K INCAR_SET="ENCUT=$ENC" \
  sbatch --job-name=CAL_E${ENC}_k${K%%x*} --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 \
         --ntasks=1 --cpus-per-task=1 --time=01:30:00 slurm/run_vasp.slurm
done
