# `run_vasp.slurm`: job genérico de VASP

Es el script que **corre VASP**. Funciona como una plantilla: **no se lanza a mano**. Lo llaman los scripts `submit_*.sh` (ver [README_submits.md](README_submits.md)), que deciden cuántos procesos e hilos usar y qué parámetros cambiar en cada corrida.

Todas las corridas pasan por este script, así que todas se preparan, se lanzan y se registran de la misma forma. Eso permite comparar los tiempos entre sí.

---

## Recursos que pide por defecto

| Opción | Valor |
|---|---|
| Partición | `phys_fast` |
| Tiempo | 1 h 30 min |
| Memoria | 16 GB |
| Nodo | `granado-compute-17` |
| Reserva | `halzate_10` |
| Salida de Slurm | `logs/<nombre>_<jobid>.out` |

El encabezado **no** dice cuántos procesos ni cuántas CPUs usar. Eso lo pone el `submit_*.sh` con `--ntasks` y `--cpus-per-task`. Lo que se pase en la línea de `sbatch` reemplaza lo del encabezado, por ejemplo `--time`, `--mem` o `--partition`.

---

## Variables que recibe

Todas son opcionales. El `submit_*.sh` las pone antes de `sbatch`.

| Variable | Para qué sirve | Valor por defecto |
|---|---|---|
| `CASE` | Carpeta con `INCAR`, `KPOINTS` y `POSCAR` | `entradas/base` |
| `KPAR`, `NCORE` | Parámetros de paralelismo de VASP | `1`, `1` |
| `KMESH` | Malla de puntos k, por ejemplo `12x12x1` | La del `KPOINTS` |
| `INCAR_SET` | Etiquetas extra para el INCAR, separadas por `;`, por ejemplo `"ENCUT=600;ISYM=-1"` | Ninguna |
| `OMP_THREADS` | Número de hilos OpenMP, si debe ser distinto de `--cpus-per-task` | Igual a `--cpus-per-task` |
| `LAUNCHER` | Con qué se lanza VASP: `srun` o `mpirun` | `srun` |
| `SRUN_MPI` | Protocolo que usa `srun` para hablar con MPI | `pmix` |
| `VASP_MODULE` | Módulo de VASP que se carga | `vasp/6.3.0-gnu9-openmp` |
| `PARTE`, `REP` | Etiquetas para el análisis, por ejemplo `A1` y `2` | `NA`, `1` |

---

## Qué hace, paso a paso

### 1. Crea una carpeta propia para la corrida
Crea `runs/<nombre>_<jobid>/` y copia ahí `INCAR`, `KPOINTS` y `POSCAR` desde `BASE`, y `POTCAR` desde `entradas/`. Después entra a esa carpeta.

Cada corrida queda separada, así que dos jobs nunca se pisan entre sí.

### 2. Ajusta el INCAR y el KPOINTS
- La función `set_tag NOMBRE VALOR` borra la etiqueta del INCAR si ya existe y la vuelve a escribir al final con el valor nuevo.
- Borra `NPAR`, porque choca con `NCORE`.
- Escribe `KPAR` y `NCORE`.
- Aplica cada etiqueta de `INCAR_SET`.
- Si se pasó `KMESH`, reemplaza la **línea 4** de `KPOINTS`. Por ejemplo, `12x12x1` queda como `12 12 1`.

### 3. Carga VASP y revisa las librerías
- Carga `VASP_MODULE`. Con `vasp/5.4.4-intel` se puede comparar con la versión de producción, que solo usa MPI.
- **Arreglo para la versión con OpenMP:** el módulo de VASP 6.3 carga una FFTW sin OpenMP, pero el programa necesita `libfftw3_omp.so.3`. Por eso el script carga `fftw/3.3.8-gnu9-openmp` a mano y agrega su ruta a `LD_LIBRARY_PATH`.
- Con `ldd` revisa si a `vasp_std` le falta alguna librería. Si falta, **se detiene con un mensaje claro** en lugar de fallar más tarde dentro de `srun`.

### 4. Configura los hilos OpenMP

| Variable | Valor | Por qué |
|---|---|---|
| `OMP_NUM_THREADS` | `OMP_THREADS` o `--cpus-per-task` | Número de hilos por proceso |
| `OMP_PLACES` | `cores` | Un hilo por núcleo |
| `OMP_PROC_BIND` | `close` | Los hilos de un proceso quedan juntos, en núcleos vecinos |
| `OMP_STACKSIZE` | `512m` | Memoria de pila de cada hilo; VASP necesita bastante |
| `OPENBLAS_NUM_THREADS` | `1` | Evita que OpenBLAS cree sus propios hilos además de los de OpenMP (sobresuscripción). Se agregó después de detectar ese problema |
| `OMP_NESTED` | `FALSE` | No se crean hilos dentro de otros hilos |
| `OMP_DISPLAY_AFFINITY` | `TRUE` | Cada hilo imprime en qué núcleo quedó |
| `OMP_DISPLAY_ENV` | `VERBOSE` | Imprime la configuración OpenMP final, que sirve de evidencia |

**Para qué sirve `OMP_THREADS`:** en Granado, 1 CPU de Slurm es 1 hilo de hyperthreading. Con `--cpus-per-task=2 OMP_THREADS=1`, cada proceso recibe un **núcleo físico completo** pero corre con un solo hilo. Así se aísla el efecto del hyperthreading. Lo usan A.1c, B.1 y C.2.

### 5. Guarda la afinidad de los procesos
Antes de correr VASP, cada proceso MPI escribe en `afinidad.txt` en qué CPUs quedó amarrado. Tarda unos segundos. Si falla, el job sigue igual (`|| true`).

### 6. Corre VASP y mide el tiempo
Anota la hora antes y después de VASP, y la diferencia es el tiempo de pared (`t_wall_s`). Hay tres formas de lanzarlo:

| Caso | Comando |
|---|---|
| `LAUNCHER=srun` (por defecto) | `srun --mpi=pmix --cpu-bind=verbose,cores ...`. El Open MPI 4 de Granado necesita `pmix`; sin eso sale el error `OPAL ERROR: Unreachable` |
| `mpirun` + módulo Intel | `mpirun` con `I_MPI_PIN_DOMAIN=omp` y `I_MPI_DEBUG=4`, que imprime el mapa de núcleos |
| `mpirun` + Open MPI | `mpirun --map-by slot:PE=<hilos> --bind-to core --report-bindings` |

La salida de VASP va a `vasp.out`.

### 7. Guarda el resumen en `meta.txt`
Es el archivo que lee el análisis:

```
tag, jobid, parte, rep,
nmpi, nomp, omp_threads, kpar, ncore,
case, kmesh, incar_set,
partition, modulo, launcher, srun_mpi, nodes,
t_wall_s, fecha
```

Además, `modulos.txt` guarda la lista de módulos cargados.

### 8. Limpia
Borra `WAVECAR`, `CHG`, `CHGCAR`, `PROCAR`, `DOSCAR`, `EIGENVAL` y la copia de `POTCAR`, que son archivos grandes y no se usan en el análisis.

---

## Qué deja cada corrida

```
runs/<nombre>_<jobid>/
├── INCAR, KPOINTS, POSCAR   ← las entradas que se usaron de verdad, ya modificadas
├── vasp.out                 ← salida de VASP, con el mapa de afinidad de hilos
├── OUTCAR, OSZICAR, ...     ← resultados de VASP
├── afinidad.txt             ← CPUs de cada proceso MPI
├── meta.txt                 ← parámetros y tiempo, para el análisis
└── modulos.txt              ← módulos cargados
```

---

## A tener en cuenta

- **Si VASP falla, no se escribe `meta.txt`.** El script usa `set -euo pipefail` y se detiene en el primer error. Esa corrida queda sin `meta.txt` y tampoco se borran sus archivos grandes. El motivo del error queda en `vasp.out` y en `logs/`.
- **Hay que lanzarlo desde la raíz del proyecto.** `ROOT` es el directorio desde donde se hizo `sbatch`, y de ahí salen `entradas/`, `runs/` y `logs/`. Los `submit_*.sh` ya hacen `cd` a la raíz antes de lanzar.
- **La carpeta `logs/` debe existir.** Slurm no la crea, y si falta, el job falla sin dejar salida.
