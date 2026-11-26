# Scripts de verificación (`slurm/`)

Antes de lanzar las corridas de VASP, que consumen presupuesto, estos scripts comprueban tres cosas en el nodo `granado-compute-16/17` (partición `phys_fast`, reserva `halzate_10`):

1. Cómo es el nodo: sockets, núcleos y si tiene hyperthreading.
2. Si "1 CPU" de Slurm es un **núcleo físico** o solo un **hilo de hyperthreading**.
3. Si los procesos MPI y los hilos OpenMP quedan bien amarrados a sus núcleos, sin compartirlos y sin repartirse entre los dos sockets.

Todos los jobs son muy cortos (2 a 5 minutos) y escriben su salida en `logs/`.

| Archivo | Cómo se corre | Pregunta que responde |
|---|---|---|
| `00_verificar_afinidad.slurm` | `sbatch slurm/00_verificar_afinidad.slurm` | ¿Cómo es el nodo y quedan bien 4 procesos × 6 hilos? |
| `01_verificar_ht.slurm` | `sbatch slurm/01_verificar_ht.slurm` | Dentro de un job de 24 CPUs, ¿dónde caen procesos e hilos con distintas combinaciones? |
| `02_verificar_asignacion.sh` | `bash slurm/02_verificar_asignacion.sh` | Si el job completo es pequeño, ¿cuántas CPUs reserva y cobra Slurm? |
| `omp_check.f90` | Lo compilan los scripts | Programa auxiliar: cada hilo OpenMP dice en qué CPU está. |

Todos los comandos se lanzan desde la carpeta `examen_martinez/`.

---

## Antes de empezar

- Crear la carpeta de logs, si no existe: `mkdir -p logs`
- Para el script 02, compilar antes `omp_check`. Ver la sección del script 02.

---

## `omp_check.f90`: programa auxiliar

Es un programa pequeño en Fortran con OpenMP. Cada hilo imprime una línea como esta:

```
host=granado-compute-16 rank=1 hilo=3/6 cpu=9
```

Se lee así: "soy el hilo 3 de 6, del proceso MPI 1, y estoy corriendo en la CPU 9".

Cómo funciona:
- Usa `sched_getcpu()`, una función de la librería de C de Linux, para saber en qué CPU está el hilo en ese instante.
- Toma el número de proceso de la variable `SLURM_PROCID`. Si no corre bajo Slurm, pone `-`.
- Usa `!$omp critical` para que los hilos escriban uno por uno y las líneas no se mezclen.

Para compilarlo:

```bash
gfortran -fopenmp omp_check.f90 -o omp_check
```

> `sched_getcpu()` da una foto de un solo instante. Con `OMP_PROC_BIND=close` los hilos quedan amarrados y no se mueven, así que la foto es confiable.

---

## `00_verificar_afinidad.slurm`: primer chequeo

**Recursos:** 4 procesos MPI × 6 CPUs = 24 CPUs, 5 minutos.

Hace cuatro cosas:

1. **Describe el nodo.** Con `lscpu` y `numactl -H` muestra el modelo de procesador, los sockets, los núcleos, los hilos por núcleo, los nodos NUMA y el mapa *CPU → núcleo → socket*.
2. **Muestra qué asignó Slurm.** Con `scontrol show job` imprime `NumCPUs`, `NumTasks`, `CPUs/Task` y `TRES`.
3. **Revisa los procesos MPI (3a).** Lanza `srun --cpu-bind=verbose,cores` y cada proceso dice qué CPUs tiene asignadas (`taskset`).
4. **Revisa los hilos OpenMP (3b).** Con `OMP_NUM_THREADS=6`, `OMP_PLACES=cores` y `OMP_PROC_BIND=close`, corre `omp_check`. Salen 24 líneas, ordenadas por proceso y por hilo.

**Al terminar**, revisar cuánto se facturó:

```bash
sacct -j <JOBID> -X --format=JobID,AllocCPUS,Elapsed,CPUTimeRAW
```

- `AllocCPUS = 24`: cada CPU de Slurm es un núcleo físico. Todo está bien.
- `AllocCPUS = 48`: Slurm cuenta los hilos de hyperthreading por separado, así que cobra el doble. Hay que ajustar la configuración.

---

## `01_verificar_ht.slurm`: segundo chequeo

**Recursos:** 24 procesos × 1 CPU, 5 minutos.

Toda la asignación del job queda fija, y dentro de ella se prueban varias formas de repartir el trabajo.

La función `mask` lanza un `srun` con los parámetros que se le pasen, y cada proceso imprime las CPUs donde quedó amarrado.

### Parte 1: dónde caen los procesos MPI

| Prueba | Qué se quiere ver |
|---|---|
| `-n1 -c24` | El conjunto completo de CPUs que recibió el job. |
| `-n1 -c1` | Dónde cae un solo proceso. |
| `-n2 -c1` | Si dos procesos de 1 CPU **comparten núcleo físico**, es decir, si cada uno queda en un hilo de hyperthreading del mismo núcleo. |
| `-n2 -c2` | Si pidiendo 2 CPUs por proceso, cada uno queda en su propio núcleo físico. |
| `-n24 -c1` | La configuración de solo MPI (caso A.1). |
| `-n12 -c2` | 12 procesos, uno por núcleo físico. |

### Parte 2: dónde caen los hilos OpenMP

Usa `omp_check` (lo compila el propio script) con `OMP_PROC_BIND=close`:

| Prueba | Qué se quiere ver |
|---|---|
| 1 proceso × 24 hilos, `OMP_PLACES=cores` | Hilos repartidos por núcleo. |
| 1 proceso × 24 hilos, `OMP_PLACES=threads` | Hilos repartidos por hilo de hardware. Al compararlo con el anterior se ve si los hilos se apilan en los mismos núcleos. |
| 2 procesos × 12 hilos, `OMP_PLACES=cores` | Híbrido. Lo esperado es que cada proceso quede en un socket. |

Si `gfortran` no está disponible, esta parte se salta. En ese caso, la afinidad de los hilos se puede ver con `OMP_DISPLAY_AFFINITY=true` en la salida de VASP.

---

## `02_verificar_asignacion.sh`: tercer chequeo

**Este no se manda con `sbatch`.** Se corre con `bash` desde el nodo de login, y el script envía **6 jobs independientes** de 2 minutos:

| Job | `--ntasks` | `--cpus-per-task` | CPUs pedidas |
|---|---|---|---|
| `asig_n1c1` | 1 | 1 | 1 |
| `asig_n2c1` | 2 | 1 | 2 |
| `asig_n4c1` | 4 | 1 | 4 |
| `asig_n2c2` | 2 | 2 | 4 |
| `asig_n1c4` | 1 | 4 | 4 |
| `asig_n2c12` | 2 | 12 | 24 |

**Por qué hace falta si ya existe el 01:** en el 01 todo corre dentro de un job grande de 24 CPUs. Aquí cada combinación es un **job propio**, así que se ve cuánto reserva y **cobra** Slurm cuando el job es pequeño. Por ejemplo, si pido 1 CPU, ¿me cobra 1 o 2?

Cada job:
1. Imprime `NumCPUs`, el número de CPUs que Slurm asignó de verdad.
2. Muestra en qué CPUs quedó cada proceso.
3. Si `cpus-per-task > 1` y existe `slurm/omp_check`, corre los hilos OpenMP con `OMP_PLACES=cores` y con `OMP_PLACES=threads`.

Las salidas quedan en `logs/asig_n<N>c<C>_<jobid>.out`.

### Detalles a tener en cuenta

- **Necesita `slurm/omp_check` ya compilado.** El script no lo compila. Si el ejecutable no existe, la parte de OpenMP **se salta sin avisar**. Para compilarlo:
  ```bash
  cd slurm && gfortran -fopenmp omp_check.f90 -o omp_check
  ```
- **Usa otra versión del compilador.** Este script carga `gnu8/8.3.0`, mientras que el 00 y el 01 usan `gnu9`. Conviene compilar `omp_check` con el mismo módulo que se carga al correrlo, para que no falle por la librería de OpenMP (`libgomp`).

---

## Cómo saber si la afinidad está bien

Compara la salida de los procesos y de `omp_check` con el mapa de `lscpu -e` del script 00.

**Bien:**
- Cada proceso o hilo tiene una CPU distinta, en un núcleo físico distinto.
- Los hilos de un mismo proceso MPI quedan en el mismo socket.
- `AllocCPUS` en `sacct` coincide con las CPUs pedidas.

**Mal:**
- Dos hilos o procesos comparten CPU o núcleo físico. Están compitiendo por el mismo hardware.
- Los hilos de un mismo proceso quedan repartidos entre los dos sockets. Esto hace más lento el acceso a memoria.
- `AllocCPUS` es el doble de lo pedido. Slurm está cobrando hilos de hyperthreading.
