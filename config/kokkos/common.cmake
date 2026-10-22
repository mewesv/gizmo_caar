# Initial cache settings; command-line -D options may override these defaults.
set(CMAKE_CXX_STANDARD 17 CACHE STRING "GIZMO's cluster toolchain baseline")
set(CMAKE_CXX_STANDARD_REQUIRED ON CACHE BOOL "Require the chosen C++ standard")
set(CMAKE_INSTALL_LIBDIR lib CACHE STRING "Consistent install layout")
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared Kokkos libraries")
set(Kokkos_ENABLE_SERIAL ON CACHE BOOL "Provide the serial backend")
set(Kokkos_ENABLE_LIBDL ON CACHE BOOL "Allow optional Kokkos Tools plugins")
set(Kokkos_ENABLE_TESTS OFF CACHE BOOL "Build dependency tests separately")
set(Kokkos_ENABLE_EXAMPLES OFF CACHE BOOL "Build dependency examples separately")
