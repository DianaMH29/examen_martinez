#!/bin/bash
#SBATCH --job-name=check_ht
#SBATCH --partition=phys_fast
#SBATCH --ntasks=24
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --mem=2000M
#SBATCH --output=logs/%x_%j.out
#SBATCH -w granado-compute-17
#SBATCH --reservation=halzate_10
#
# Segundo chequeo: Aqui se ve, dentro de esa asignacion,
# donde caen los procesos y los hilos en las configuraciones.
#
# Uso: sbatch slurm/01_verificar_ht.slurm

module load vasp/6.3.0-gnu9-openmp
module load gnu8/8.3.0 2>/dev/null
mask () { srun "$@" --cpu-bind=cores bash -c 'echo "  rank=$SLURM_PROCID cpus=$(taskset -cp $$ | cut -d: -f2)"' | sort -t= -k2,2n; }

echo "=== Asignacion completa del job"; mask -n1 -c24
echo "=== p=1  (1 proceso, 1 CPU)";                         mask -n1 -c1
echo "=== p=2  MPI con -c1: ¿los 2 procesos comparten nucleo?"; mask -n2 -c1
echo "=== p=2  MPI con -c2: 1 proceso por nucleo fisico";     mask -n2 -c2
echo "=== p=24 MPI con -c1 (como en A.1)";                    mask -n24 -c1
echo "=== 12 procesos con -c2 (1 por nucleo fisico)";        mask -n12 -c2

if command -v gfortran >/dev/null && gfortran -fopenmp -O0 "$SLURM_SUBMIT_DIR/slurm/omp_check.f90" -o /tmp/omp_$SLURM_JOB_ID; then
  export OMP_PROC_BIND=close
  for places in cores threads; do
    echo "=== OpenMP 1x24, OMP_PLACES=$places"
    OMP_NUM_THREADS=24 OMP_PLACES=$places srun -n1 -c24 --cpu-bind=cores /tmp/omp_$SLURM_JOB_ID | sort -t= -k4,4n
  done
  echo "=== Hibrido 2x12, OMP_PLACES=cores"
  OMP_NUM_THREADS=12 OMP_PLACES=cores srun -n2 -c12 --cpu-bind=cores /tmp/omp_$SLURM_JOB_ID | sort
  rm -f /tmp/omp_$SLURM_JOB_ID
else
  echo "(sin gfortran: la afinidad de hilos se vera con OMP_DISPLAY_AFFINITY en vasp.out)"
fi
