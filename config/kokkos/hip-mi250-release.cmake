include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type")
set(Kokkos_ENABLE_HIP ON CACHE BOOL "Enable HIP")
set(Kokkos_ARCH_VEGA90A ON CACHE BOOL "Target AMD MI250")
set(Kokkos_ARCH_ZEN3 ON CACHE BOOL "Target Frontier's host CPUs")
# Explicit flags prevent Kokkos adding a second bare gfx90a target. The setting
# is supported by the pinned 4.6.02 source (cmake/kokkos_arch.cmake).
set(Kokkos_IMPL_AMDGPU_FLAGS "--offload-arch=gfx90a:xnack-" CACHE STRING "Target MI250 with XNACK disabled")
