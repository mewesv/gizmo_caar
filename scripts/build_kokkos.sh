#!/usr/bin/env bash
# Build the pinned dependency independently of GIZMO's Makefile/configuration.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build_kokkos.sh PROFILE [-- CMAKE_OPTIONS...]

Profiles:
  serial-debug         Portable CPU build, including View bounds checks
  openmp-debug         OpenMP CPU build, including View bounds checks
  openmp-release       OpenMP CPU release build
  cuda-a100-release    CUDA, NVIDIA A100 (sm_80)
  cuda-h100-release    CUDA, NVIDIA H100 (sm_90)
  hip-mi250-release    HIP, AMD MI250 (gfx90a:xnack+), Zen 3 host

Environment overrides:
  CMAKE                 CMake executable (default: cmake)
  KOKKOS_BUILD_CXX       Compiler executable (default: c++, nvcc_wrapper, hipcc)
  KOKKOS_BUILD_JOBS      Parallel build jobs (default: 8)
  KOKKOS_BUILD_DIR       Build directory (default: build/kokkos/PROFILE)
  KOKKOS_INSTALL_PREFIX  Install directory (default: install/kokkos/PROFILE)

Initialize source first: git submodule update --init external/kokkos
Load compiler/CUDA/ROCm/MPI modules before invoking this script. Use distinct
build/install directories when switching toolchains or changing profile options.
EOF
}

if [[ $# == 0 || ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
profile=$1
shift
if [[ ${1:-} == -- ]]; then shift; fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source_dir="$root/external/kokkos"
device_flags=
expected_arch=
case "$profile" in
    serial-debug) backend=serial; default_compiler=c++ ;;
    openmp-debug|openmp-release) backend=openmp; default_compiler=c++ ;;
    cuda-a100-release)
        backend=cuda; default_compiler="$source_dir/bin/nvcc_wrapper"
        expected_arch=KOKKOS_ARCH_AMPERE80
        device_flags='--expt-relaxed-constexpr --expt-extended-lambda -arch=sm_80' ;;
    cuda-h100-release)
        backend=cuda; default_compiler="$source_dir/bin/nvcc_wrapper"
        expected_arch=KOKKOS_ARCH_HOPPER90
        device_flags='--expt-relaxed-constexpr --expt-extended-lambda -arch=sm_90' ;;
    hip-mi250-release)
        backend=hip; default_compiler=hipcc
        expected_arch=KOKKOS_ARCH_VEGA90A
        device_flags='--offload-arch=gfx90a:xnack+ -march=znver3' ;;
    *) printf 'Unknown Kokkos profile: %s\n' "$profile" >&2; usage >&2; exit 2 ;;
esac

if [[ ! -f "$source_dir/CMakeLists.txt" ]]; then
    printf 'Initialize the pinned source: git submodule update --init external/kokkos\n' >&2
    exit 2
fi
cmake=${CMAKE:-cmake}
compiler=${KOKKOS_BUILD_CXX:-$default_compiler}
jobs=${KOKKOS_BUILD_JOBS:-8}
if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then printf 'KOKKOS_BUILD_JOBS must be positive\n' >&2; exit 2; fi
command -v "$cmake" >/dev/null || { printf 'CMake executable not found: %s\n' "$cmake" >&2; exit 2; }
compiler=$(command -v "$compiler") || { printf 'Compiler executable not found: %s\n' "$compiler" >&2; exit 2; }
build_dir=${KOKKOS_BUILD_DIR:-$root/build/kokkos/$profile}
prefix=${KOKKOS_INSTALL_PREFIX:-$root/install/kokkos/$profile}
# These paths are consumed by the legacy Makefile, which has no general path
# escaping. Reject Make/shell metacharacters rather than write unsafe metadata.
case "$prefix" in
    *[!a-zA-Z0-9_./+-]*) printf 'Install prefix must not contain whitespace or Make metacharacters\n' >&2; exit 2 ;;
esac
mkdir -p -- "$build_dir" "$prefix"
build_dir=$(cd -- "$build_dir" && pwd -P)
prefix=$(cd -- "$prefix" && pwd -P)

actual=$(git -C "$source_dir" rev-parse HEAD)
pinned=$(git -C "$root" ls-files --stage -- external/kokkos | awk '$3 == 0 {print $2}')
if [[ -z "$pinned" || "$actual" != "$pinned" ]]; then
    printf 'Kokkos checkout differs from the recorded gitlink. Run git submodule update --init external/kokkos.\n' >&2
    exit 2
fi
if ! git -C "$source_dir" diff --quiet HEAD --; then
    printf 'Kokkos source has tracked changes; commit them and update the parent gitlink first.\n' >&2
    exit 2
fi

# CMake retains backend/compiler choices in its cache. Keep a separate directory
# for each source revision, compiler, profile and option combination.
compiler_version=$("$compiler" --version)
compiler_id=${compiler_version%%$'\n'*}
options=$(printf '%q ' "$@")
identity="$actual|$profile|$compiler|$compiler_id|$prefix|$options"
if [[ -f "$prefix/share/gizmo/build-identity.txt" ]] &&
   [[ $(cat "$prefix/share/gizmo/build-identity.txt") != "$identity" ]]; then
    printf 'Install identity changed. Select a fresh KOKKOS_INSTALL_PREFIX.\n' >&2
    exit 2
fi
if [[ -f "$build_dir/gizmo-build-identity.txt" ]] &&
   [[ $(cat "$build_dir/gizmo-build-identity.txt") != "$identity" ]]; then
    printf 'Build identity changed. Select a fresh KOKKOS_BUILD_DIR and KOKKOS_INSTALL_PREFIX.\n' >&2
    exit 2
fi
printf '%s\n' "$identity" > "$build_dir/gizmo-build-identity.txt"
"$cmake" -S "$source_dir" -B "$build_dir" -C "$root/config/kokkos/$profile.cmake" \
    "-DCMAKE_CXX_COMPILER=$compiler" "-DCMAKE_INSTALL_PREFIX=$prefix" "$@"
"$cmake" --build "$build_dir" --parallel "$jobs"
"$cmake" --install "$build_dir"

header="$prefix/include/KokkosCore_config.h"
installed_backend=serial
if grep -Eq '^#define KOKKOS_ENABLE_OPENMP([[:space:]]|$)' "$header"; then installed_backend=openmp; fi
if grep -Eq '^#define KOKKOS_ENABLE_HIP([[:space:]]|$)' "$header"; then installed_backend=hip; fi
if grep -Eq '^#define KOKKOS_ENABLE_CUDA([[:space:]]|$)' "$header"; then installed_backend=cuda; fi
if [[ "$installed_backend" != "$backend" ]]; then
    printf 'Installed backend differs from the requested profile; no GIZMO metadata written.\n' >&2
    exit 2
fi
if [[ -n "$expected_arch" ]] && ! grep -Eq "^#define $expected_arch([[:space:]]|$)" "$header"; then
    printf 'Installed architecture differs from the profile; no GIZMO metadata written.\n' >&2
    exit 2
fi
mkdir -p -- "$prefix/share/gizmo"
printf '%s\n' "$identity" > "$prefix/share/gizmo/build-identity.txt"
{
    printf '# Generated by scripts/build_kokkos.sh; local installation metadata.\n'
    printf 'GIZMO_KOKKOS_PROFILE := %s\n' "$profile"
    printf 'GIZMO_KOKKOS_SOURCE_COMMIT := %s\n' "$actual"
    printf 'GIZMO_KOKKOS_DEVICE_FLAGS := %s\n' "$device_flags"
} > "$prefix/share/gizmo/kokkos.mk"
{
    printf 'profile=%s\nsource_commit=%s\ncompiler=%s\n' "$profile" "$actual" "$compiler"
    printf 'configure_command='; printf '%q ' "$cmake" -S "$source_dir" -B "$build_dir" \
        -C "$root/config/kokkos/$profile.cmake" "-DCMAKE_CXX_COMPILER=$compiler" \
        "-DCMAKE_INSTALL_PREFIX=$prefix" "$@"; printf '\n'
    printf '%s\n' "$compiler_version"
} > "$prefix/share/gizmo/build-info.txt"
printf '\nInstalled Kokkos %s (%s).\n' "$actual" "$profile"
printf 'Build GIZMO with its matching machine profile and KOKKOS_PREFIX=%s\n' "$prefix"
