include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type")
set(Kokkos_ENABLE_OPENMP ON CACHE BOOL "Enable the host OpenMP backend")
