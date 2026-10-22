include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type")
set(Kokkos_ENABLE_CUDA ON CACHE BOOL "Enable CUDA")
set(Kokkos_ARCH_AMPERE80 ON CACHE BOOL "Target NVIDIA A100")
