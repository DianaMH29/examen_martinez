# Scripts de análisis (`analisis/`)

Estos scripts toman los resultados de las corridas que quedan en `runs/` (generadas por [`run_vasp.slurm`](../slurm/README_run_vasp.md)) y producen las **tablas** y **figuras** del informe.

Hay que correrlos **en orden**: primero `extraer.py`, que junta todo en un CSV, y después cualquiera de los otros tres, que leen ese CSV.

```
runs/*/meta.txt, OUTCAR, OSZICAR
              │
              ▼
        extraer.py  ──►  datos/tiempos.csv
              │
   ┌──────────┼───────────────┐
   ▼          ▼               ▼
fuerte.py  hibrido_debil.py  precision.py
 (A.3)      (B.1, B.2)        (C.1, C.2)
```

| Script | Tarea | Qué produce |
|---|---|---|
| `extraer.py` | — | `datos/tiempos.csv`: una fila por corrida |
| `fuerte.py` | A.3 | Aceleración y eficiencia del escalamiento fuerte, con ajuste de Amdahl |
| `hibrido_debil.py` | B.1, B.2 | Eficiencia débil y comparación de las configuraciones híbridas |
| `precision.py` | C.1, C.2 | Reproducibilidad de la energía y error contra costo |

---

## Cómo se corren

Desde la raíz del proyecto (`examen_martinez/`):

```bash
python analisis/extraer.py
python analisis/fuerte.py
python analisis/hibrido_debil.py
python analisis/precision.py
```

Las rutas se calculan a partir de la ubicación de cada script, así que funcionan desde cualquier carpeta.

**Requisitos:** Python 3 con `pandas`, `numpy` y `matplotlib` (`extraer.py` solo usa la librería estándar).

**Dónde quedan las salidas:**
- Tablas: `datos/*.csv`
- Figuras: `analisis/figuras/*.pdf` y `*.png` (200 dpi). La carpeta se crea sola.

---

## `extraer.py`: junta todas las corridas en un CSV

Recorre cada carpeta `runs/*/` que tenga `meta.txt` y escribe **una fila por corrida** en `datos/tiempos.csv`.

### De dónde sale cada dato

| Fuente | Columnas |
|---|---|
| `meta.txt` | `tag`, `parte`, `rep`, `nmpi`, `nomp`, `omp_threads`, `kpar`, `ncore`, `kmesh`, `incar_set`, `partition`, `modulo`, `nodes`, `jobid`, `t_wall_s` |
| `OUTCAR` (última coincidencia) | `elapsed_s`, `maxmem_kb`, `nkpts`, `nbands`, `nplwv`, `toten_eV`, `e_sigma0_eV` |
| `OUTCAR` (líneas `LOOP:`) | `t_scf_medio_s`: tiempo real promedio de cada paso SCF |
| `OUTCAR` | `convergido` = 1 si aparece `EDIFF is reached` |
| `OSZICAR` | `n_scf`: número de pasos SCF. `mag`: magnetización final |
| Calculadas | `p = nmpi × nomp` (CPUs de Slurm). `carpeta` = nombre de la carpeta en `runs/` |

### Dos tiempos distintos
- **`elapsed_s`** es el *Elapsed time* que reporta VASP en el OUTCAR. **Es el tiempo principal** del análisis.
- **`t_wall_s`** lo mide `run_vasp.slurm` alrededor de `srun` e incluye el arranque de MPI. Los demás scripts lo usan solo si falta `elapsed_s`.

### Qué imprime
- Cuántas corridas leyó.
- Una lista **"Revisar"** con las corridas que no terminaron (sin `elapsed_s`) o no convergieron.
- Si una carpeta está rota, la avisa con `[aviso]` y sigue con las demás.

> Las corridas que fallaron antes de escribir `meta.txt` **no aparecen**, porque el script solo busca carpetas con ese archivo.

---

## `fuerte.py`: escalamiento fuerte (A.3)

Usa las corridas `A1` (solo MPI), `A2` (solo OpenMP) y `A1c` (MPI con 1 proceso por núcleo físico), **solo las que convergieron**.

### Las dos figuras

**1. `fuerte_S_E`: eje en CPUs de Slurm** (la definición del examen)
- A1 y A2, con `x = p` = 1 a 24.

**2. `fuerte_nucleos`: eje en núcleos físicos**
- En Granado, 1 CPU de Slurm es 1 hilo de hyperthreading, así que `p` CPUs equivalen a `p/2` núcleos físicos, con 2 procesos o hilos en cada uno.
- **A1 y A2:** la referencia es `p = 1` (un proceso con el núcleo entero). Los puntos son `p ≥ 2`, con `x = p/2`. Así, el punto `x = 1` es `p = 2` y muestra cuánto gana el hyperthreading.
- **A1c:** `x` = número de procesos (cada proceso tiene un núcleo completo). En la figura de CPUs, `x = 2 × procesos`, porque Slurm cobra 2 CPUs por proceso.

Cada figura tiene dos paneles: **aceleración S** y **eficiencia E**. Incluyen la línea ideal, la línea `E = 0.5` como guía y, en gris, el **límite por reparto de k-points**, explicado más abajo.

### Qué calcula

Para cada punto se usa la media y la desviación de las repeticiones:

| Cantidad | Fórmula | Qué significa |
|---|---|---|
| Aceleración | `S = t(1) / t(x)` | Cuántas veces más rápido es que con 1 |
| Error de S | Propagación de las desviaciones de `t(1)` y `t(x)` | Barras de error |
| Eficiencia | `E = S / x` | Qué fracción del ideal se logra |
| **Amdahl** | `1/S = f + (1−f)/x` | `f` = fracción serial. Se ajusta por mínimos cuadrados usando los puntos con `x > 1` |
| **Karp–Flatt** | `f_e(x) = (1/S − 1/x) / (1 − 1/x)` | Fracción serial "experimental" en cada punto |
| **Amdahl + sobrecosto** | `t(x)/t(1) = f + (1−f)/x + k·(x−1)` | Agrega un costo `k` que crece con `x`, como la comunicación |

**Cómo leer Karp–Flatt:**
- Si **crece** con `x`, hay sobrecosto: comunicación, ancho de banda de memoria, etc.
- Si **decrece**, el eje no está midiendo recursos equivalentes. Por ejemplo, el hyperthreading en `x = 2`.

**Cuándo se dibuja cada modelo:** si el ajuste de Amdahl da `f < 1`, se dibuja Amdahl. Si da `f ≥ 1` (cuando hay puntos con `S < 1` que Amdahl no puede describir), se dibuja el modelo con sobrecosto, con línea punteada.

**Límite por k-points:** con `x` grupos, el grupo más cargado tiene `⌈Nk / x⌉` k-points, así que la aceleración máxima posible es `Nk / ⌈Nk / x⌉`. Forma una escalera: por ejemplo, con `Nk = 10`, pasar de 5 a 8 procesos no mejora nada. `Nk` se toma de las corridas A1.

### Salidas
- `analisis/figuras/fuerte_S_E.{pdf,png}`
- `analisis/figuras/fuerte_nucleos.{pdf,png}`
- `datos/resumen_fuerte.csv`: modo, eje, `x`, media, desviación, `S`, `E`, sus errores y Karp–Flatt.
- En pantalla: los valores de `f` y `k` de cada serie y la tabla completa.

---

## `hibrido_debil.py`: escalamiento débil (B.1) e híbrido (B.2)

Solo usa las corridas que convergieron.

### B.1: escalamiento débil
- Usa las corridas `B1`: `n` procesos, **1 por núcleo físico**, con **16 k-points por proceso**.
- `n` = número de procesos = núcleos físicos.
- **Eficiencia débil:** `E_w = t(1) / t(n)`. Lo ideal es `E_w = 1`, es decir, el mismo tiempo con el doble de trabajo y el doble de núcleos.
- La memoria total se estima como `memoria del proceso 0 × n`, porque VASP solo reporta la del proceso 0.
- Salidas: `datos/tabla_debil.csv` y `analisis/figuras/debil.{pdf,png}`.

### B.2: híbrido MPI × OpenMP
- Usa las corridas `B2` y, para la configuración **1×24**, toma `A2` con `p = 24`, que es la misma corrida.
- Para cada configuración `N_MPI × N_OMP` calcula tiempo medio, desviación, repeticiones, memoria del proceso 0, memoria total estimada (`× N_MPI`) y pasos SCF promedio.
- Imprime cuál es la **configuración óptima**, la de menor tiempo.
- Gráfico de barras con el tiempo de cada configuración. Las 24 CPUs de Slurm son 12 núcleos físicos.
- Salidas: `datos/tabla_hibrido.csv` y `analisis/figuras/hibrido.{pdf,png}`.

Si todavía no hay corridas de una parte, lo avisa y sigue con la otra.

---

## `precision.py`: reproducibilidad (C.1) y precisión contra costo (C.2)

### C.1: ¿cambia la energía con el número de procesos?
- Usa las corridas `A1` y `A2` con `p` = 1, 4, 16 y 24.
- Referencia: la energía media (`energy(sigma→0)`) de `p = 1`.
- Para cada corrida calcula:
  - `dE` = diferencia con la referencia, en eV.
  - `n_eps_mach = |dE| / (|E| · ε)`, la diferencia medida en unidades de precisión de máquina, con `ε = 2⁻⁵²` (doble precisión).
- También imprime el **piso de resolución**: el OUTCAR solo trae 8 decimales (10⁻⁸ eV), así que una diferencia menor que `10⁻⁸ / (|E| · ε)` veces `ε` **no se puede ver**.
- Salida: `datos/tabla_reproducibilidad.csv`.

### C.2: ¿cuánto error se gana por cada segundo de más?
Hay dos series, y solo se usan las corridas que convergieron:

| Serie | Etiqueta | Parámetro que cambia |
|---|---|---|
| ENCUT | `C2E` | `ENCUT`, que se lee de `incar_set` |
| Malla k | `C2K` | N de la malla N×N×1, que se lee de `kmesh` |

- **Referencia:** el valor **más alto** del parámetro, no la corrida más lenta.
- **Error:** `|E − E_ref|` en **meV por átomo**, con 5 átomos.
- **Rendimiento:** `−Δlog₁₀(error) / Δlog₁₀(tiempo)` entre puntos seguidos. Dice cuántas décadas de error se ganan por cada década de tiempo. **Si baja de ~1, ya no vale la pena subir la precisión.**
- Figura log–log de error contra tiempo, con cada punto anotado con su valor y una línea guía en 1 meV/átomo.
- Salidas: `datos/tabla_C2E.csv`, `datos/tabla_C2K.csv` y `analisis/figuras/precision_vs_costo.{pdf,png}`.

---

## Todas las salidas

| Archivo | Lo genera |
|---|---|
| `datos/tiempos.csv` | `extraer.py` |
| `datos/resumen_fuerte.csv` | `fuerte.py` |
| `datos/tabla_debil.csv` | `hibrido_debil.py` |
| `datos/tabla_hibrido.csv` | `hibrido_debil.py` |
| `datos/tabla_reproducibilidad.csv` | `precision.py` |
| `datos/tabla_C2E.csv`, `datos/tabla_C2K.csv` | `precision.py` |
| `analisis/figuras/fuerte_S_E.*`, `fuerte_nucleos.*` | `fuerte.py` |
| `analisis/figuras/debil.*`, `hibrido.*` | `hibrido_debil.py` |
| `analisis/figuras/precision_vs_costo.*` | `precision.py` |

---

## A tener en cuenta

- **Las corridas se agrupan solo por `parte`.** Ningún script filtra por `modulo`. Si en `runs/` quedan corridas de A.2 o B.2 hechas con el módulo viejo junto con las de `submit_final.sh`, se promedian juntas. Según el comentario de `submit_A2_fuerte_omp.sh`, las corridas viejas se movieron a `runs_modulo_viejo/`; hay que mantenerlas fuera de `runs/`.
- **C.2 puede mezclar dos versiones.** `submit_C2_precision.sh` (8 procesos MPI) y `submit_final.sh` (4 procesos, 1 por núcleo) usan las mismas etiquetas `C2E` y `C2K`. Si las dos están en `runs/`, `precision.py` las junta en la misma curva. La etiqueta del eje dice "4 procesos MPI", así que se espera solo la versión de `submit_final.sh`.
- **Hay textos fijos en las figuras.** Las leyendas de C.2 dicen "malla 12×12×1" y "ENCUT 400 eV". Si el caso base elegido en la calibración es otro, hay que cambiarlas en `precision.py`.
- **B.1 necesita el punto `n = 1`.** Sin él, `E_w` no se puede calcular y el script falla.
- **C.1 no filtra por convergencia,** a diferencia de los demás análisis. Una corrida que no convergió entraría en la tabla de reproducibilidad.
