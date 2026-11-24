#!/bin/bash
#SBATCH --job-name=DM-BENCH-CHECK
#SBATCH --partition=phys_fast
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=6
#SBATCH --time=00:05:00
#SBATCH --mem=2000M
#SBATCH -w granado-compute-16
#SBATCH --reservation=halzate_10
#SBATCH --output=logs/%x_%j.out

# Job que responde tres preguntas antes de gastar presupuesto:
#  1) Topologia real del nodo.
#  2) Si "1 CPU" de Slurm es un nucleo fisico o un hilo de hyperthreading.
#  3) Si --cpu-bind=cores + OMP_PLACES/OMP_PROC_BIND dejan cada hilo en su nucleo y socket.
# Uso:  sbatch slurm/00_verificar_afinidad.slurm

ulimit -s unlimited
module load vasp/6.3.0-gnu9-openmp

echo "=== 1) Topologia del nodo: $(hostname)"
lscpu | grep -E 'Model name|^CPU\(s\)|Socket|Core\(s\)|Thread|NUMA'
echo "--- Mapa CPU -> nucleo -> socket"
lscpu -e=CPU,CORE,SOCKET,NODE
command -v numactl >/dev/null && numactl -H

echo; echo "=== 2) Lo que Slurm asigno"
scontrol show job "$SLURM_JOB_ID" | grep -E 'NumCPUs|NumTasks|CPUs/Task|TRES'
echo "SLURM_JOB_CPUS_PER_NODE=$SLURM_JOB_CPUS_PER_NODE"

echo; echo "=== 3a) Mascara de cada proceso MPI (--cpu-bind=cores)"
srun --cpu-bind=verbose,cores --cpus-per-task=6 \
     bash -c 'echo "rank=$SLURM_PROCID cpus=$(taskset -cp $$ | cut -d: -f2)"'

echo; echo "=== 3b) Hilos OpenMP dentro de cada proceso"
export OMP_NUM_THREADS=6 OMP_PLACES=cores OMP_PROC_BIND=close
if gfortran -fopenmp -O0 "$SLURM_SUBMIT_DIR/slurm/omp_check.f90" -o "/tmp/omp_check_$SLURM_JOB_ID" 2>/dev/null; then
  srun --cpu-bind=cores --cpus-per-task=6 "/tmp/omp_check_$SLURM_JOB_ID" | sort -t= -k3,3n -k4,4n
  rm -f "/tmp/omp_check_$SLURM_JOB_ID"
else
  echo "gfortran no disponible; usar OMP_DISPLAY_AFFINITY en las corridas de VASP"
fi

echo; echo "Despues de que termine, revise la facturacion con:"
echo "  sacct -j $SLURM_JOB_ID -X --format=JobID,AllocCPUS,Elapsed,CPUTimeRAW"
echo "AllocCPUS deberia ser 24. Si sale 48, Slurm cuenta hilos y hay que ajustar."
