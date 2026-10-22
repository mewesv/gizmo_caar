include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type")
set(Kokkos_ENABLE_DEBUG ON CACHE BOOL "Enable Kokkos checks")
set(Kokkos_ENABLE_DEBUG_BOUNDS_CHECK ON CACHE BOOL "Check View bounds")
