# Scripts `submit_*.sh`: envío de las corridas

Cada `submit_*.sh` corresponde a una tarea del examen. Envía a la cola un grupo de jobs que **todos corren [`run_vasp.slurm`](README_run_vasp.md)**; lo único que cambia entre ellos son los procesos, los hilos y los parámetros de VASP.

Se corren con `bash` (no con `sbatch`), desde cualquier carpeta, porque cada script hace `cd` a la raíz del proyecto:

```bash
bash slurm/submit_calibracion.sh
```

---

## Resumen

| Script | Tarea | Qué mide | Jobs |
|---|---|---|---|
| `submit_calibracion.sh` | 0 | Elegir el caso base (que tarde entre 15 y 60 min en 1 CPU) | 3 |
| `submit_A1_fuerte_mpi.sh` | A.1 | Escalamiento fuerte, solo MPI | 21 |
| `submit_A1c_nucleos.sh` | A.1 (control) | Igual que A.1, pero con 1 proceso por **núcleo físico** | 15 |
| `submit_A2_fuerte_omp.sh` | A.2 | Escalamiento fuerte, solo OpenMP *(versión vieja)* | 21 |
| `submit_B1_debil.sh` | B.1 | Escalamiento débil por k-points | 12 |
| `submit_B2_hibrido.sh` | B.2 | Híbrido MPI × OpenMP con 24 CPUs *(versión vieja)* | 21 |
| `submit_C2_precision.sh` | C.2 | Precisión contra costo (ENCUT y malla k) | 17 |
| `submit_final.sh` | A.2 + B.2 + C.2 | Fase final con el módulo corregido, en una sola cadena | 48 |

El número de jobs supone `REPS=3`.

**Orden sugerido:** calibración → ajustar `config.sh` → A.1 / A.1c / B.1 → `submit_final.sh`.

---

## `config.sh`: configuración compartida

Los submits la cargan con `source slurm/config.sh`; la calibración no la usa.

| Qué | Valor | Para qué |
|---|---|---|
| `T1_MIN` | `34` | Minutos que tarda el caso base en 1 CPU. **Se ajusta después de la calibración.** Solo sirve para calcular los límites de tiempo |
| `REPS` | `3` | Repeticiones de cada punto |
| `tlim p [fac]` | `10 + ⌈fac·T1_MIN / p⌉` minutos (`fac=3` si no se da) | Límite de tiempo para `p` procesos: holgado, pero lo bastante corto para que la cola pueda acomodar el job en un hueco (*backfill*) |
| `dep` | `--dependency=afterany:<último job>` | Encadena los jobs: cada uno espera a que termine el anterior, para no ocupar varios cupos del nodo compartido al mismo tiempo. Solo lo usa `submit_final.sh` |

Ejemplo con `T1_MIN=34`: `tlim 1` = 112 min, `tlim 8` = 23 min, `tlim 24` = 15 min.

---

## Tarea 0: `submit_calibracion.sh`

Prueba **tres candidatos de caso base** en 1 proceso con 1 CPU:

| Job | ENCUT | Malla k |
|---|---|---|
| `CAL_E400_k12` | 400 eV | 12×12×1 |
| `CAL_E500_k15` | 500 eV | 15×15×1 |
| `CAL_E600_k18` | 600 eV | 18×18×1 |

- Se elige el que tarde **entre 15 y 60 minutos**. Su tiempo se pone como `T1_MIN` en `config.sh`.
- Costo máximo: 3 × 1.5 h = 4.5 h-núcleo.
- Estas corridas también sirven como el punto **p = 1** de la Parte A y como primeros puntos de C.2.
- Etiqueta: `PARTE=CAL`.

---

## Tarea A.1: `submit_A1_fuerte_mpi.sh`

**Escalamiento fuerte, solo MPI:** el mismo problema con cada vez más procesos.

- `p` procesos MPI con 1 CPU cada uno (`--cpus-per-task=1`), sin OpenMP.
- `p` = 1, 2, 4, 8, 12, 16, 24.
- `KPAR = p`: cada proceso se encarga de su parte de los k-points. `NCORE = 1`.
- Límite de tiempo: `tlim p`.
- Nombres: `A1_p08_r2`, etc. Etiqueta `PARTE=A1`.

---

## A.1 control: `submit_A1c_nucleos.sh`

Es la misma prueba que A.1, pero con **1 proceso por núcleo físico**.

En Granado, 1 CPU de Slurm es 1 **hilo de hyperthreading**. Así, en A.1 con `p = 24`, en realidad hay 2 procesos compartiendo cada núcleo físico. Aquí, en cambio:

- `--cpus-per-task=2`: cada proceso recibe un núcleo completo (sus 2 hilos de hardware).
- `OMP_THREADS=1`: aun así, el proceso corre con un solo hilo.
- Slurm cobra 2 CPUs por proceso, así que el máximo es 12 procesos (24 CPUs).
- `p` = 1, 2, 4, 6, 12. `KPAR = p`, `NCORE = 1`.
- Nombres: `A1c_n04_r1`, etc. Etiqueta `PARTE=A1c`.

Al compararla con A.1 se separa **la aceleración real** del **efecto del hyperthreading**.

---

## Tarea A.2: `submit_A2_fuerte_omp.sh` *(versión vieja)*

> Se corrió con el módulo original `vasp/6.3.0-gnu9-openmp` y sus resultados quedaron en `runs_modulo_viejo/`. **La versión válida de A.2 está en `submit_final.sh`.**

**Escalamiento fuerte, solo OpenMP:** 1 proceso MPI con `p` hilos.

- `--ntasks=1 --cpus-per-task=p`, con `p` = 1, 2, 4, 8, 12, 16, 24.
- `KPAR = 1`, `NCORE = 1` (con OpenMP, VASP pone `NCORE = 1` de todos modos).
- Límite de tiempo: `tlim p 6`, el doble de holgura que en A.1, porque OpenMP escala peor.
- Etiqueta `PARTE=A2`.

---

## Tarea B.1: `submit_B1_debil.sh`

**Escalamiento débil:** el trabajo **por proceso** se mantiene igual y el problema crece con el número de procesos.

- `n` procesos MPI, **1 por núcleo físico** (`--cpus-per-task=2`, `OMP_THREADS=1`), para que el hyperthreading no se mezcle con el costo de comunicación.
- `ISYM=-1` (sin simetría): VASP no reduce los k-points, así que hay exactamente N1 × N2 de ellos.
- `KPAR = n` y una malla que crece con `n`, de modo que **cada proceso tiene siempre 16 k-points**:

| n | Malla | k-points | k-points por proceso | CPUs facturadas |
|---|---|---|---|---|
| 1 | 4×4×1 | 16 | 16 | 2 |
| 2 | 4×8×1 | 32 | 16 | 4 |
| 4 | 8×8×1 | 64 | 16 | 8 |
| 8 | 8×16×1 | 128 | 16 | 16 |

- Memoria: 30 GB. Límite: `T1_MIN + 30` minutos.
- Nombres: `B1_n04_r1`, etc. Etiqueta `PARTE=B1`.

Si el escalamiento fuera perfecto, todas las corridas tardarían lo mismo.

---

## Tarea B.2: `submit_B2_hibrido.sh` *(versión vieja)*

> La versión válida de B.2 está en `submit_final.sh`.

**Híbrido MPI × OpenMP** con 24 CPUs fijas, repartidas de distintas formas:

| Procesos MPI × hilos | 24×1 | 12×2 | 8×3 | 6×4 | 4×6 | 2×12 | 1×24 |
|---|---|---|---|---|---|---|---|

- `KPAR` = número de procesos MPI, `NCORE = 1`.
- Partición `phys_general`. Límite: `T1_MIN + 15` minutos.
- Nombres: `B2_8x3_r1`, etc. Etiqueta `PARTE=B2`.

---

## Tarea C.2: `submit_C2_precision.sh`

**Precisión contra costo.** Todas las corridas usan 8 procesos MPI (`KPAR = 8`) y una sola repetición. Hay dos series:

| Serie | Qué cambia | Qué queda fijo | Valores | Etiqueta |
|---|---|---|---|---|
| ENCUT | `ENCUT` | Malla base | 300, 350, 400, 450, 500, 600, 700, 800, 900 eV | `C2E` |
| Malla k | `KMESH` = K×K×1 | ENCUT base | K = 6, 9, 12, 15, 18, 21, 24, 30 | `C2K` |

- Los valores más altos de cada serie (900 eV y 30×30×1) se usan como **referencia "exacta"** para medir el error de los demás.
- Partición `phys_general`, sin reserva ni nodo fijo.

`submit_final.sh` trae otra versión más corta de C.2.

---

## Fase final: `submit_final.sh`

Corre **A.2, B.2 y C.2 de nuevo** con el módulo corregido **`vasp/6.3.0-gnu9-openmpV2`** (OpenBLAS recompilado) y `OPENBLAS_NUM_THREADS=1`. Esto corrige la sobresuscripción de hilos que afectó a las versiones viejas.

**Todo va en una sola cadena:** cada job espera a que termine el anterior (`afterany`). El primero espera al último job que ya tengas en la cola.

**El orden es por repetición**, para que, si se acaba el tiempo, quede al menos una repetición completa de todo:

| Repetición | A.2 | B.2 | C.2 |
|---|---|---|---|
| 1 | 7 jobs | 6 jobs | 9 jobs |
| 2 | 7 | 6 | — |
| 3 | 7 | 6 | — |

Total: 48 jobs. Para correr solo 2 repeticiones: `REPS=2 bash slurm/submit_final.sh`.

Detalle de cada parte:
- **A.2:** 1 proceso con `p` = 1, 2, 4, 8, 12, 16, 24 hilos. Nombres `A2v2_p08_r1`, etc.
- **B.2:** 24×1, 12×2, 8×3, 6×4, 4×6, 2×12. **No se corre 1×24**, porque es igual a A.2 con `p = 24`. Nombres `B2v2_6x4_r1`, etc.
- **C.2:** 4 procesos MPI, 1 por núcleo físico (`-c2`, `OMP_THREADS=1`, `KPAR = 4`).
  - ENCUT = 300, 400, 500, 700 eV.
  - Malla K×K×1 con K = 6, 9, 12, 18, 24.
- Todos usan `phys_fast`, la reserva `halzate_10` y el nodo `granado-compute-17`. Límite de tiempo: `T1_MIN + 20` min (`T1_MIN + 30` para la serie de malla k).

La función `enviar` lanza cada job con `sbatch --parsable`, guarda su ID para encadenar el siguiente e imprime `nombre -> jobid`.

---

## A tener en cuenta

- **Hay que ajustar `config.sh` después de la calibración.** Si `T1_MIN` queda mal, los límites de tiempo quedan demasiado cortos (los jobs se cortan) o demasiado largos (esperan más en la cola).
- **Solo `submit_final.sh` encadena los jobs.** Los otros submits envían todos sus jobs a la vez, y Slurm los corre en paralelo si hay espacio.
