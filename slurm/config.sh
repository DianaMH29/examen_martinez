# Ajustar DESPUES de la calibracion:
# T1_MIN = minutos que tarda el caso base en 1 nucleo (se usa solo para los limites de tiempo).
T1_MIN=34
REPS=3
# limite de tiempo en minutos para p nucleos: holgado, pero corto ayuda al backfill de la cola
tlim () { local p=$1 fac=${2:-3}; echo $(( 10 + (fac*T1_MIN + p - 1) / p )); }

# Encadenamiento: cada job nuevo espera a que termine el anterior (afterany),
# para no ocupar varios cupos del nodo compartido al mismo tiempo.
ULTIMO=$(squeue -u "$USER" -h -o %i | sort -n | tail -1)
dep () { [[ -n $ULTIMO ]] && echo "--dependency=afterany:$ULTIMO"; }
