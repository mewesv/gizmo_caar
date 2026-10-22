# Included after machine settings. Without KOKKOS_PREFIX the legacy settings
# retain their values and the submodule need not be initialized.
ifneq ($(strip $(KOKKOS_PREFIX)),)
ifneq ($(words $(KOKKOS_PREFIX)),1)
$(error KOKKOS_PREFIX must not contain whitespace)
endif
override KOKKOS_PREFIX := $(abspath $(KOKKOS_PREFIX))
GIZMO_KOKKOS_HEADER := $(KOKKOS_PREFIX)/include/KokkosCore_config.h
ifeq ($(wildcard $(GIZMO_KOKKOS_HEADER)),)
$(error KOKKOS_PREFIX has no include/KokkosCore_config.h: $(KOKKOS_PREFIX))
endif
GIZMO_KOKKOS_BACKENDS := $(shell awk '$$1 == "\043define" && $$2 ~ /^KOKKOS_ENABLE_(CUDA|HIP|OPENMP|SERIAL)$$/ {sub(/^KOKKOS_ENABLE_/, "", $$2); print $$2}' $(GIZMO_KOKKOS_HEADER))
ifneq ($(filter CUDA,$(GIZMO_KOKKOS_BACKENDS)),)
GIZMO_KOKKOS_BACKEND := CUDA
else ifneq ($(filter HIP,$(GIZMO_KOKKOS_BACKENDS)),)
GIZMO_KOKKOS_BACKEND := HIP
else ifneq ($(filter OPENMP,$(GIZMO_KOKKOS_BACKENDS)),)
GIZMO_KOKKOS_BACKEND := OPENMP
else ifneq ($(filter SERIAL,$(GIZMO_KOKKOS_BACKENDS)),)
GIZMO_KOKKOS_BACKEND := SERIAL
else
$(error KOKKOS_PREFIX must provide CUDA, HIP, OpenMP or Serial)
endif

GIZMO_KOKKOS_CORE_LIB := $(firstword $(wildcard $(KOKKOS_PREFIX)/lib/libkokkoscore.* $(KOKKOS_PREFIX)/lib64/libkokkoscore.*))
ifeq ($(GIZMO_KOKKOS_CORE_LIB),)
$(error KOKKOS_PREFIX has no lib/libkokkoscore.* or lib64/libkokkoscore.*)
endif
GIZMO_KOKKOS_LIBDIR := $(patsubst %/,%,$(dir $(GIZMO_KOKKOS_CORE_LIB)))
GIZMO_KOKKOS_COMMA := ,
# Retain CUDA runtime/stub paths and other machine-specific linker settings,
# removing the previous Kokkos prefix's library/rpath settings.
GIZMO_KOKKOS_PREVIOUS_PREFIX := $(strip $(KOKKOS_PATH))
GIZMO_KOKKOS_PREVIOUS_LDFLAGS := $(strip $(KOKKOS_LDFLAGS))
ifneq ($(GIZMO_KOKKOS_PREVIOUS_PREFIX),)
GIZMO_KOKKOS_RETAINED_LDFLAGS := $(filter-out -L$(GIZMO_KOKKOS_PREVIOUS_PREFIX)% -Wl$(GIZMO_KOKKOS_COMMA)-rpath$(GIZMO_KOKKOS_COMMA)$(GIZMO_KOKKOS_PREVIOUS_PREFIX)%,$(GIZMO_KOKKOS_PREVIOUS_LDFLAGS))
else
GIZMO_KOKKOS_RETAINED_LDFLAGS := $(GIZMO_KOKKOS_PREVIOUS_LDFLAGS)
endif

KOKKOS_PATH = $(KOKKOS_PREFIX)
KOKKOS_CPPFLAGS = -I$(KOKKOS_PREFIX)/include
KOKKOS_INCL = $(KOKKOS_CPPFLAGS)
KOKKOS_LDFLAGS = -L$(GIZMO_KOKKOS_LIBDIR) -Wl,-rpath,$(GIZMO_KOKKOS_LIBDIR) $(GIZMO_KOKKOS_RETAINED_LDFLAGS) $(KOKKOS_EXTRA_LDFLAGS)
KOKKOS_LIBS_PATH = $(KOKKOS_LDFLAGS)
KOKKOS_LIBS = -lkokkoscore -lkokkoscontainers $(KOKKOS_EXTRA_LIBS)

# Source-built profiles supply architecture flags. External installations without
# this file keep the matching machine profile's existing device flags.
-include $(KOKKOS_PREFIX)/share/gizmo/kokkos.mk
ifneq ($(strip $(GIZMO_KOKKOS_PROFILE)),)
GIZMO_KOKKOS_SITE_FLAGS := $(filter-out -arch=% --offload-arch=% -march=% --expt-relaxed-constexpr --expt-extended-lambda,$(KOKKOS_CXXFLAGS))
KOKKOS_CXXFLAGS = $(GIZMO_KOKKOS_SITE_FLAGS) $(GIZMO_KOKKOS_DEVICE_FLAGS)
endif
ifeq ($(GIZMO_KOKKOS_BACKEND),CUDA)
ifeq ($(wildcard $(KOKKOS_PREFIX)/bin/nvcc_wrapper),)
$(error CUDA installation has no bin/nvcc_wrapper; select an installed Kokkos prefix)
endif
GPU_CXX = $(KOKKOS_PREFIX)/bin/nvcc_wrapper --std=c++17
KOKKOS_LIBS += -lcudart -lcuda
GPU_CFLAGS = $(KOKKOS_CPPFLAGS) $(KOKKOS_CXXFLAGS)
else ifeq ($(GIZMO_KOKKOS_BACKEND),HIP)
GPU_CXX = hipcc --std=c++17
GPU_CFLAGS = $(KOKKOS_CPPFLAGS) $(KOKKOS_CXXFLAGS)
else
GPU_CXX = $(CXX)
GPU_CFLAGS = $(KOKKOS_CPPFLAGS) $(KOKKOS_CPU_FLAGS)
endif
GPU_LDFLAGS = $(KOKKOS_LDFLAGS)
endif
