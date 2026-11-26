! Imprime en que CPU corre cada hilo OpenMP (verificacion de afinidad).
! Compilar: gfortran -fopenmp omp_check.f90 -o omp_check

program omp_check
  use omp_lib
  use iso_c_binding, only: c_int
  implicit none

  interface
    ! sched_getcpu() de la libreria de C (glibc): devuelve el CPU donde corre el hilo
    function sched_getcpu() bind(C, name="sched_getcpu") result(cpu)
      import :: c_int
      integer(c_int) :: cpu
    end function sched_getcpu
  end interface

  character(len=64) :: host, rank
  integer :: stat
  integer :: hostnm

  stat = hostnm(host)   ! extension de gfortran: nombre real del nodo de computo
  call get_environment_variable("SLURM_PROCID", rank, status=stat)
  if (stat /= 0) rank = "-"

  !$omp parallel
  !$omp critical
  write(*, '(a,a,a,a,a,i0,a,i0,a,i0)') "host=", trim(host), " rank=", trim(rank), &
       " hilo=", omp_get_thread_num(), "/", omp_get_num_threads(), " cpu=", sched_getcpu()
  !$omp end critical
  !$omp end parallel
end program omp_check
