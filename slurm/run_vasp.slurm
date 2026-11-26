#!/bin/bash
#SBATCH --partition=phys_fast
#SBATCH --time=01:30:00
#SBATCH --mem=16000M
#SBATCH -w granado-compute-16
#SBATCH --reservation=halzate_10
#SBATCH --output=logs/%x_%j.out
#
# Job generico de VASP. NO se lanza a mano: lo usan los scripts submit_*.sh.
# Variables de entorno que lee (todas opcionales):
#   CASE       carpeta con INCAR/KPOINTS/POSCAR   (default: entradas/base)
#   KPAR NCORE parametros de paralelismo de VASP  (default: 1 1)
#   KMESH      malla k, ej. "12x12x1"             (sobrescribe linea 4 de KPOINTS)
#   INCAR_SET  etiquetas extra, ej. "ENCUT=600;ISYM=-1"
#   LAUNCHER   srun (default) o mpirun
#   VASP_MODULE modulo de VASP (default: vasp/6.3.0-gnu9-openmp)
#   PARTE REP  etiquetas para el analisis (A1, A2, B1, B2, C2, CAL ...)
set -euo pipefail

ROOT=${SLURM_SUBMIT_DIR}
CASE=${CASE:-entradas/base}
KPAR=${KPAR:-1}
NCORE=${NCORE:-1}
NMPI=${SLURM_NTASKS:-1}
NOMP=${SLURM_CPUS_PER_TASK:-1}
RUN=$ROOT/runs/${SLURM_JOB_NAME}_${SLURM_JOB_ID}

mkdir -p "$RUN"
cp "$ROOT/$CASE"/{INCAR,KPOINTS,POSCAR} "$RUN"/
cp "$ROOT/entradas/POTCAR" "$RUN"/
cd "$RUN"

set_tag () {   # set_tag NOMBRE VALOR  -> reemplaza o agrega la etiqueta en INCAR
  sed -i "/^[[:space:]]*$1[[:space:]]*=/d" INCAR
  echo "$1 = $2" >> INCAR
}
sed -i '/^[[:space:]]*NPAR[[:space:]]*=/d' INCAR
set_tag KPAR  "$KPAR"
set_tag NCORE "$NCORE"
if [[ -n "${INCAR_SET:-}" ]]; then
  IFS=';' read -ra PARES <<< "$INCAR_SET"
  for par in "${PARES[@]}"; do set_tag "${par%%=*}" "${par#*=}"; done
fi
if [[ -n "${KMESH:-}" ]]; then
  sed -i "4s/.*/${KMESH//x/ }/" KPOINTS
fi

# Binario: por defecto el de VASP 6 con OpenMP (necesario para A.2 y B.2).
# VASP_MODULE=vasp/5.4.4-intel permite comparar con el binario de produccion (solo MPI).
VASP_MODULE=${VASP_MODULE:-vasp/6.3.0-gnu9-openmp}
ulimit -s unlimited
module load "$VASP_MODULE"
if [[ $VASP_MODULE == *openmp* ]]; then
  # El modulo de VASP 6.3 carga fftw/3.3.8-gnu9 (sin OpenMP), pero el binario necesita
  # libfftw3_omp.so.3, que solo esta en la version -openmp. 
  module load fftw/3.3.8-gnu9-openmp
  export LD_LIBRARY_PATH=/opt/ohpc/pub/libs/fftw/3.3.8-gnu9-openmp/lib:${LD_LIBRARY_PATH:-}
fi
# Chequeo rapido: si falta alguna libreria, abortar con un mensaje claro en vez de fallar dentro de srun
if ldd "$(which vasp_std)" | grep -q "not found"; then
  echo "ERROR: librerias faltantes para vasp_std:"; ldd "$(which vasp_std)" | grep "not found"; exit 1
fi

export OMP_NUM_THREADS=${OMP_THREADS:-$NOMP}   # OMP_THREADS=1 con -c2: 1 proceso por nucleo fisico, 1 hilo
export OMP_PLACES=cores
export OMP_PROC_BIND=close
export OMP_STACKSIZE=512m
export OPENBLAS_NUM_THREADS=1           # agregado tras diagnosticar sobresuscripcion; no afecta corridas con 1 hilo (A.1, A.1c, B.1)
export OMP_NESTED=FALSE
export OMP_DISPLAY_AFFINITY=TRUE        # cada hilo imprime su nucleo (si libgomp lo soporta)
export OMP_DISPLAY_ENV=VERBOSE          # imprime OMP_PLACES resueltos -> evidencia de afinidad

# Evidencia de afinidad por proceso MPI 
srun --cpu-bind=verbose,cores --cpus-per-task="$NOMP" \
     bash -c 'echo "rank=$SLURM_PROCID host=$(hostname) cpus=$(taskset -cp $$ | cut -d: -f2)"' \
     > afinidad.txt 2>&1 || true

LAUNCHER=${LAUNCHER:-srun}
T0=$(date +%s.%N)
if [[ $LAUNCHER == srun ]]; then
  # Open MPI 4 de Granado necesita que srun le hable en PMIx (sin esto: "OPAL ERROR: Unreachable")
  srun --mpi="${SRUN_MPI:-pmix}" --cpu-bind=verbose,cores --cpus-per-task="$NOMP" vasp_std > vasp.out 2>&1
elif [[ $VASP_MODULE == *intel* ]]; then          # Intel MPI
  export I_MPI_PIN_DOMAIN=omp I_MPI_DEBUG=4
  mpirun -np "$NMPI" vasp_std > vasp.out 2>&1
else                                               # Open MPI
  mpirun -np "$NMPI" --map-by "slot:PE=$NOMP" --bind-to core --report-bindings vasp_std > vasp.out 2>&1
fi
T1=$(date +%s.%N)

cat > meta.txt <<EOF
tag=${SLURM_JOB_NAME}
jobid=${SLURM_JOB_ID}
parte=${PARTE:-NA}
rep=${REP:-1}
nmpi=${NMPI}
nomp=${NOMP}
omp_threads=${OMP_THREADS:-$NOMP}
kpar=${KPAR}
ncore=${NCORE}
case=${CASE}
kmesh=$(sed -n 4p KPOINTS | xargs)
incar_set=${INCAR_SET:-}
partition=${SLURM_JOB_PARTITION}
modulo=${VASP_MODULE}
launcher=${LAUNCHER}
srun_mpi=${SRUN_MPI:-pmix}
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | paste -sd+)
t_wall_s=$(awk "BEGIN{print $T1 - $T0}")
fecha=$(date -Iseconds)
EOF
module list > modulos.txt 2>&1 || true
rm -f WAVECAR CHG CHGCAR PROCAR DOSCAR EIGENVAL POTCAR
