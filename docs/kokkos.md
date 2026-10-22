# Building the pinned Kokkos dependency

`external/kokkos` is an optional Git submodule pinned to Kokkos **4.6.02**, commit
`d8e9af0316d77cff5059748958a81a8961db2a0b`. The submodule records source; a separate
build and installation supplies the generated headers and libraries. GIZMO keeps
its existing Makefile build and machine profiles.

Using an installed cluster module remains supported. If `KOKKOS_PREFIX` is unset,
the existing machine settings apply and the submodule does not need to be checked
out. The build helper does not install CMake, compilers, CUDA, ROCm, MPI, or system
packages. Provide those tools through your package manager or cluster modules.

## Initialize source

For an existing checkout:

```sh
git submodule update --init external/kokkos
```

For a new checkout, `git clone --recurse-submodules` initializes it as well. Avoid
`git submodule update --remote` for reproducible builds: `git submodule update`
checks out the commit recorded by GIZMO. To deliberately upgrade Kokkos, check out
the desired tag/commit inside the submodule, validate the configuration, then
commit the updated `external/kokkos` gitlink in the parent repository.

## Build profiles

Profiles live in `config/kokkos/` and use CMake initial cache files. They target
the branch's C++17 toolchains and enable the Kokkos Tools loading interface.

| Profile | Backend | Purpose |
| --- | --- | --- |
| `serial-debug` | Serial | CPU checks without an OpenMP dependency |
| `openmp-debug` | OpenMP | CPU checks with View bounds checking |
| `openmp-release` | OpenMP | CPU performance work |
| `cuda-a100-release` | CUDA, AMPERE80 | NVIDIA A100 |
| `cuda-h100-release` | CUDA, HOPPER90 | NVIDIA H100 |
| `hip-mi250-release` | HIP, VEGA90A + ZEN3 | AMD MI250 with XNACK disabled |

Run from the repository root, after loading the required toolchain:

```sh
./scripts/build_kokkos.sh openmp-debug
```

The default build and install locations are `build/kokkos/PROFILE` and
`install/kokkos/PROFILE`, both ignored by Git. CPU profiles use `c++`, CUDA uses
the pinned source's `nvcc_wrapper`, and HIP uses `hipcc`.

Build Kokkos with a compiler and C++ standard library compatible with the compiler
used for GIZMO and its MPI wrapper. For example:

```sh
KOKKOS_BUILD_CXX=mpicxx ./scripts/build_kokkos.sh openmp-debug
```

For CUDA, use the CUDA profile's default `nvcc_wrapper` and select its host
compiler with `NVCC_WRAPPER_DEFAULT_COMPILER` as appropriate for the cluster:

```sh
NVCC_WRAPPER_DEFAULT_COMPILER=mpicxx \
  ./scripts/build_kokkos.sh cuda-a100-release
```

On Frontier, load the matching AMD/ROCm toolchain before building the HIP
profile. The profile requests `gfx90a:xnack-`, matching the Frontier GIZMO
machine block. Run with XNACK disabled (`HSA_XNACK=0`); the build scripts do not
set that runtime variable. GPU profiles must be validated on their target
machines. XNACK-off disables automatic GPU page-fault-driven migration: managed
allocations can be accessed through mapped host memory, while ordinary host
allocations need explicit registration or another device-accessible allocation
strategy before GPU use. This mode has not yet been validated for GIZMO's full
managed-memory access paths on Frontier.

When switching an existing XNACK-on build to XNACK-off, use fresh dependency
build/install directories and rebuild GIZMO completely. For example, to retain
the old installation:

```sh
KOKKOS_BUILD_DIR="$PWD/build/kokkos/hip-mi250-xnack-off" \
KOKKOS_INSTALL_PREFIX="$PWD/install/kokkos/hip-mi250-xnack-off" \
  ./scripts/build_kokkos.sh hip-mi250-release
./scripts/build_gizmo.sh frontier \
  --kokkos-prefix "$PWD/install/kokkos/hip-mi250-xnack-off"
```

Use new directory names if these already contain an earlier build. The wrapper
cleans GIZMO by default; do not use `--no-clean` for this transition.

The script accepts these environment overrides:

| Variable | Purpose |
| --- | --- |
| `CMAKE` | CMake executable or full path |
| `KOKKOS_BUILD_CXX` | Compiler executable or full path |
| `KOKKOS_BUILD_JOBS` | Positive parallel job count, default 8 |
| `KOKKOS_BUILD_DIR` | Separate build directory |
| `KOKKOS_INSTALL_PREFIX` | Separate install prefix |

Additional CMake options follow `--`:

```sh
KOKKOS_BUILD_JOBS=4 ./scripts/build_kokkos.sh serial-debug -- \
  -DCMAKE_CXX_FLAGS="-isystem /path/to/sdk/usr/include/c++/v1"
```

Use fresh build/install directories when changing the source pin, compiler,
profile contents, or configure options. The helper records an identity,
including checksums of the profile and common cache settings, and refuses to
reuse its directories with a different identity. It also checks the checkout
against the recorded gitlink and rejects tracked source changes. Architecture
and backend changes should have their own profile rather than contradict an
existing profile's name and generated GIZMO flags.

## Select the installation in GIZMO

### Frontier build wrapper

Load your compiler/library environment first, then use the wrapper to select
`SYSTYPE=Frontier` and pass the Kokkos installation to GIZMO:

```sh
source /path/to/modules.sh
./scripts/build_gizmo.sh frontier
```

The defaults are `src/Config.sh`, eight build jobs (override the latter with
`GIZMO_BUILD_JOBS` or `-j`), and the pinned submodule's installation at
`install/kokkos/hip-mi250-release` under this checkout. Build that installation
first using `./scripts/build_kokkos.sh hip-mi250-release`.

Another Kokkos installation requires an explicit override:

1. Explicit `--kokkos-prefix PATH`.
2. Exported `KOKKOS_PREFIX`.

Without either override, the wrapper uses the pinned submodule's default
installation and fails if it is missing. It does not search other installations.
`OLCF_KOKKOS_ROOT` does not override the default. `KOKKOS_INSTALL_PREFIX` sets the
dependency helper's install location only; to select a custom location for
GIZMO, pass `--kokkos-prefix` or export `KOKKOS_PREFIX` explicitly.

Explicit paths are also supported (relative paths are relative to your shell):

```sh
./scripts/build_gizmo.sh frontier --config test/my_problem/Config.sh \
  --kokkos-prefix /path/to/kokkos/install -j 8
```

Environment setup is separate from building. The wrapper does not load or
unload modules, initialize a module command, or discover/source `modules.sh` in
any directory. Your setup file can live wherever you prefer and can export the
Kokkos prefix alongside other dependency paths. Use a compiler/ROCm/MPI stack
compatible with the selected Kokkos installation; the existing Frontier
Makefile documents its expected stack. Optional physics libraries such as
HYPRE must also be provided by your environment when enabled in `Config.sh`.

The wrapper checks the config, HIP Kokkos headers/libraries, compilers, and site
paths before running Make. It cleans first by default because the legacy build
does not track changes in compiler flags. Use `--no-clean` only for incremental
builds with the same toolchain, Kokkos installation and physics config. Builds
still share `src/` object files; do not run different configurations concurrently
in one checkout. The wrapper does not build Kokkos or modify `Makefile.systype`.

Use the same environment setup in your batch job and set `HSA_XNACK=0` for this
XNACK-off GPU build. This wrapper has not yet been validated on Frontier.

### Direct Make invocation

Choose the matching machine in `src/Makefile.systype` and supply your simulation's
`src/Config.sh`. Then, from the repository root:

```sh
make clean
make -j8 KOKKOS_PREFIX="$PWD/install/kokkos/openmp-debug"
```

`make clean` is required when switching Kokkos installations/backends or compiler
flags, because the legacy Makefile does not track changes in flag values.

For a site-provided installation:

```sh
make -j8 KOKKOS_PREFIX=/path/to/site/kokkos
```

`config/kokkos/installed.mk` selects include and library paths, runtime library
search paths, and the device compiler from the selected installation. It detects
CUDA/HIP/OpenMP/Serial from `KokkosCore_config.h` and supports `lib` and `lib64`.
CUDA uses the installation's `bin/nvcc_wrapper`, HIP uses `hipcc`, and CPU builds
use the machine profile's C++ compiler. MPI/header flags, CUDA runtime paths and
other platform dependencies continue to come from the machine settings.

The repository build helper writes architecture metadata to
`PREFIX/share/gizmo/kokkos.mk`, so GIZMO receives the matching A100/H100/MI250
device flags. An external installation without that metadata uses the selected
machine profile's device flags; its backend, architecture, compiler and C++
standard must be compatible with that profile. Selecting a prefix does not load
toolchain modules or configure unrelated dependencies such as HDF5 and HYPRE.

Optional `KOKKOS_EXTRA_LDFLAGS`, `KOKKOS_EXTRA_LIBS`, and `KOKKOS_CPU_FLAGS` allow
additional site flags. Existing lower-level Makefile command-line overrides
remain available. OpenMP compiler/runtime flags still come from the machine
profile, so use its CPU/OpenMP variant for CPU profiles.

The installation also contains `share/gizmo/build-info.txt` with the Kokkos
commit, profile, compiler version and configure command. Keep that file alongside
the GIZMO build information when recording performance results. Kokkos Tools
plugins are optional separate dependencies; the internal [timer API](timers.md)
does not need a plugin to produce its reports.

## Transfer the changes to another fork

Prefer importing the parent commits with `git cherry-pick` or a `git format-patch`
series applied using `git am`. These preserve the submodule gitlink. Then run
`git submodule update --init external/kokkos` in the destination checkout.

Plain `git apply FILE.patch` applies a patch to working files without creating a
commit. `git apply --check FILE.patch` only checks applicability. For patches that
add a submodule, use `git am` or `git apply --index` so the recorded submodule
commit is placed in the index; copying `.gitmodules` alone is insufficient.

## Focused checks

```sh
python3 dev/test_kokkos_config.py
bash -n scripts/build_kokkos.sh
```

The Makefile checks use fixture headers/library placeholders to verify selection,
path replacement, retained platform flags, architecture metadata, and early
errors. They do not establish ABI compatibility or replace a real dependency and
GIZMO build on each target platform.
