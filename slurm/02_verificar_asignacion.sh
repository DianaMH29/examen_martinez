#!/bin/bash
# Tercer chequeo: jobs REALES diminutos (segundos) para ver que asigna y factura Slurm
# cuando el job completo es pequeno (en 01 eran pasos dentro de un job de 24 CPUs).

# Uso:  bash slurm/02_verificar_asignacion.sh

cd "$(dirname "$0")/.."
for nc in "1 1" "2 1" "4 1" "2 2" "1 4" "2 12"; do
  read -r N C <<< "$nc"
  sbatch --job-name=asig_n${N}c${C} --partition=phys_fast --reservation=halzate_10 -w granado-compute-17 --ntasks=$N --cpus-per-task=$C \
         --time=00:02:00 --mem=500M --output=logs/%x_%j.out \
         --wrap "echo \"ntasks=$N cpus-per-task=$C  -> \$(scontrol show job \$SLURM_JOB_ID | grep -o 'NumCPUs=[0-9]*')\";
                 srun --cpu-bind=cores bash -c 'echo \"  rank=\$SLURM_PROCID cpus=\$(taskset -cp \$\$ | cut -d: -f2)\"' | sort
                 if [ $C -gt 1 ] && [ -x slurm/omp_check ]; then
                   module load gnu8/8.3.0
                   for pl in cores threads; do
                     echo \"  -- hilos OpenMP, OMP_PLACES=\$pl\"
                     OMP_NUM_THREADS=$C OMP_PLACES=\$pl OMP_PROC_BIND=close srun --cpu-bind=cores slurm/omp_check | sort
                   done
                 fi"
done