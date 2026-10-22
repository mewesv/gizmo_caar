#!/usr/bin/env bash
# Build GIZMO using the toolchain already loaded in the caller's environment.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build_gizmo.sh frontier [OPTIONS]

  --kokkos-prefix PATH  Override the pinned submodule's installation
                        (default: install/kokkos/hip-mi250-release under checkout;
                        KOKKOS_PREFIX is also an explicit override)
  --config PATH         Physics configuration (default: src/Config.sh)
  -j, --jobs N          Parallel jobs (default: GIZMO_BUILD_JOBS or 8)
  --no-clean           Incremental build; only use with the same config/toolchain
  -h, --help           Show help

Run on Frontier after loading your toolchain (e.g. source /path/to/modules.sh).
The script selects SYSTYPE=Frontier and uses an installed HIP Kokkos. It does
not load modules, source environment scripts, or build Kokkos. A clean build
is the default.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 2; }
if [[ $# == 0 || ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
[[ $1 == frontier ]] || fail "Unknown machine '$1'; supported machine: frontier"
shift
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
config="$root/src/Config.sh"
prefix=${KOKKOS_PREFIX:-$root/install/kokkos/hip-mi250-release}
jobs=${GIZMO_BUILD_JOBS:-8}
clean=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kokkos-prefix)
            [[ $# -ge 2 && -n $2 ]] || fail '--kokkos-prefix requires a path'
            prefix=$2; shift 2 ;;
        --config)
            [[ $# -ge 2 && -n $2 ]] || fail '--config requires a path'
            config=$2; shift 2 ;;
        -j|--jobs)
            [[ $# -ge 2 ]] || fail "$1 requires a job count"
            jobs=$2; shift 2 ;;
        --no-clean) clean=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done
[[ $jobs =~ ^[1-9][0-9]*$ ]] || fail 'Job count must be a positive integer'
[[ -f $config ]] || fail "Physics config not found: $config (copy and edit src/Template_Config.sh first)"
config="$(cd -- "$(dirname -- "$config")" && pwd -P)/$(basename -- "$config")"
# These paths are passed to the legacy Makefile, which does not escape them.
case "$config" in *[!a-zA-Z0-9_./+-]*) fail 'Config path contains whitespace or Make metacharacters' ;; esac
[[ -d $prefix ]] || fail "Kokkos installation not found: $prefix; build the default with ./scripts/build_kokkos.sh hip-mi250-release, or select an installation with --kokkos-prefix"
prefix=$(cd -- "$prefix" && pwd -P)
case "$prefix" in *[!a-zA-Z0-9_./+-]*) fail 'Kokkos prefix contains whitespace or Make metacharacters' ;; esac
[[ -f $prefix/include/Kokkos_Core.hpp && -f $prefix/include/KokkosCore_config.h ]] || \
    fail "Missing Kokkos headers in $prefix/include; select the install directory, not source/build"
awk '$1 == "#define" && $2 == "KOKKOS_ENABLE_HIP" {found=1} END {exit !found}' \
    "$prefix/include/KokkosCore_config.h" || fail 'Frontier GPU builds require a HIP-enabled Kokkos installation'
compgen -G "$prefix/lib/libkokkoscore.*" >/dev/null || \
    compgen -G "$prefix/lib64/libkokkoscore.*" >/dev/null || fail "Kokkos core library missing from $prefix"
for tool in cc CC hipcc make perl; do
    command -v "$tool" >/dev/null || fail "Required executable not found: $tool (load your Frontier toolchain first)"
done
[[ -n ${CRAY_MPICH_DIR:-} && -f $CRAY_MPICH_DIR/include/mpi.h ]] || fail 'CRAY_MPICH_DIR does not provide include/mpi.h'
[[ -n ${HDF5_ROOT:-} && -f $HDF5_ROOT/include/hdf5.h ]] || fail 'HDF5_ROOT does not provide include/hdf5.h'
[[ -n ${OLCF_GSL_ROOT:-} ]] || fail 'OLCF_GSL_ROOT is unset; load your Frontier library environment first'

# Environment SYSTYPE is normalized by src/Makefile; use it rather than an
# unquoted command-line assignment, which bypasses that normalization in Make.
export SYSTYPE=Frontier
export KOKKOS_PREFIX="$prefix"
make_options=("CONFIG=$config" "KOKKOS_PREFIX=$prefix")
printf 'Machine: %s\nConfig: %s\nKokkos: %s\nJobs: %s\n' "$SYSTYPE" "$config" "$prefix" "$jobs"
if [[ $clean == 1 ]]; then
    make -C "$root/src" "${make_options[@]}" clean
fi
make -C "$root/src" -j"$jobs" "${make_options[@]}"
printf '\nBuilt: %s/src/GIZMO\nRuntime: use the same toolchain environment and export HSA_XNACK=1 in your job script.\n' "$root"
