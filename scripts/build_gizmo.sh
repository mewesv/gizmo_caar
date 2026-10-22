#!/usr/bin/env bash
# Load Frontier's toolchain and build GIZMO with an explicit Kokkos installation.
set -eo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build_gizmo.sh frontier [OPTIONS]

  --kokkos-prefix PATH  Installed HIP Kokkos (default: KOKKOS_PREFIX, then
                        KOKKOS_INSTALL_PREFIX, then install/kokkos/hip-mi250-release)
  --kokkos-module       Use kokkos/4.6.02-gpu instead of a private installation
  --config PATH         Physics configuration (default: src/Config.sh)
  -j, --jobs N          Parallel jobs (default: GIZMO_BUILD_JOBS or 8)
  --no-clean           Incremental build; only use with the same config/toolchain
  -h, --help           Show help

Loads PrgEnv-amd, amd/6.4.2, rocm/6.4.2, cray-mpich/9.0.1,
craype-accel-amd-gfx90a, cray-hdf5, cray-fftw and gsl. Loads hypre/3.0.0-mpi
only when required by Config.sh and no custom HYPRE_ROOT/HYPRE_DIR is set.
Override versions with GIZMO_FRONTIER_ROCM_VERSION, GIZMO_FRONTIER_MPICH_VERSION,
GIZMO_FRONTIER_KOKKOS_MODULE and GIZMO_FRONTIER_HYPRE_MODULE.

Run on Frontier. Kokkos must already be installed; this script does not build it.
Module changes apply only inside this script. A clean build is the default.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 2; }
if [[ $# == 0 || ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
[[ $1 == frontier ]] || fail "Unknown machine '$1'; supported machine: frontier"
shift
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
config="$root/src/Config.sh"
prefix=${KOKKOS_PREFIX:-${KOKKOS_INSTALL_PREFIX:-$root/install/kokkos/hip-mi250-release}}
jobs=${GIZMO_BUILD_JOBS:-8}
clean=1
kokkos_mode=prefix
kokkos_option_seen=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kokkos-prefix)
            [[ $# -ge 2 && -n $2 ]] || fail '--kokkos-prefix requires a path'
            [[ $kokkos_option_seen == 0 ]] || fail 'Select Kokkos only once'
            prefix=$2; kokkos_option_seen=1; shift 2 ;;
        --kokkos-module)
            [[ $kokkos_option_seen == 0 ]] || fail 'Select Kokkos only once'
            kokkos_mode=module; kokkos_option_seen=1; shift ;;
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
if [[ $kokkos_mode == prefix ]]; then
    [[ -d $prefix ]] || fail "Kokkos installation not found: $prefix; install it first or use --kokkos-module"
    prefix=$(cd -- "$prefix" && pwd -P)
fi

# Noninteractive Bash may not inherit the module function. Avoid sourcing user
# dotfiles; initialize only the site's standard module integration if necessary.
if ! type module >/dev/null 2>&1; then
    if [[ -r /etc/profile.d/modules.sh ]]; then
        source /etc/profile.d/modules.sh
    elif [[ -r /usr/share/lmod/lmod/init/bash ]]; then
        source /usr/share/lmod/lmod/init/bash
    fi
fi
type module >/dev/null 2>&1 || fail 'No module command; run this script in a Frontier login environment'
rocm_version=${GIZMO_FRONTIER_ROCM_VERSION:-6.4.2}
mpich_version=${GIZMO_FRONTIER_MPICH_VERSION:-9.0.1}
module load PrgEnv-amd
module load "amd/$rocm_version" "rocm/$rocm_version" "cray-mpich/$mpich_version" \
    craype-accel-amd-gfx90a cray-hdf5 cray-fftw gsl
# Do not leave a site Kokkos module active when a private prefix was selected.
if [[ $kokkos_mode == module ]]; then
    module load "${GIZMO_FRONTIER_KOKKOS_MODULE:-kokkos/4.6.02-gpu}"
    prefix=${OLCF_KOKKOS_ROOT:-}
    [[ -n $prefix && -d $prefix ]] || fail 'Kokkos module did not set a valid OLCF_KOKKOS_ROOT'
    prefix=$(cd -- "$prefix" && pwd -P)
else
    module unload kokkos
fi
if awk '
    {sub(/#.*/, ""); gsub(/[[:space:]]/, "")}
    /^MHD_MODIFIED_GRADIENT(=|$)/ {mg=1}
    /^MHD_MODIFIED_GRADIENT_CG_ONLY(=|$)/ {cg=1}
    /^MHD_MODIFIED_GRADIENT_USE_PARDISO(=|$)/ {pardiso=1}
    END {exit !(mg && !cg && !pardiso)}
' "$config"; then
    if [[ -n ${HYPRE_ROOT:-${HYPRE_DIR:-}} ]]; then
        module unload hypre
        unset OLCF_HYPRE_ROOT
    else
        module load "${GIZMO_FRONTIER_HYPRE_MODULE:-hypre/3.0.0-mpi}"
    fi
fi
case "$prefix" in *[!a-zA-Z0-9_./+-]*) fail 'Kokkos prefix contains whitespace or Make metacharacters' ;; esac
[[ -f $prefix/include/Kokkos_Core.hpp && -f $prefix/include/KokkosCore_config.h ]] || \
    fail "Missing Kokkos headers in $prefix/include; select the install directory, not source/build"
awk '$1 == "#define" && $2 == "KOKKOS_ENABLE_HIP" {found=1} END {exit !found}' \
    "$prefix/include/KokkosCore_config.h" || fail 'Frontier GPU builds require a HIP-enabled Kokkos installation'
compgen -G "$prefix/lib/libkokkoscore.*" >/dev/null || \
    compgen -G "$prefix/lib64/libkokkoscore.*" >/dev/null || fail "Kokkos core library missing from $prefix"
for tool in cc CC hipcc make perl; do
    command -v "$tool" >/dev/null || fail "Required executable not found: $tool"
done
[[ -n ${CRAY_MPICH_DIR:-} && -f $CRAY_MPICH_DIR/include/mpi.h ]] || fail 'CRAY_MPICH_DIR does not provide include/mpi.h'
[[ -n ${HDF5_ROOT:-} && -f $HDF5_ROOT/include/hdf5.h ]] || fail 'HDF5_ROOT does not provide include/hdf5.h'
[[ -n ${OLCF_GSL_ROOT:-} ]] || fail 'The gsl module did not set OLCF_GSL_ROOT'

# Environment SYSTYPE is normalized by src/Makefile; use it rather than an
# unquoted command-line assignment, which bypasses that normalization in Make.
export SYSTYPE=Frontier
export KOKKOS_PREFIX="$prefix"
make_options=("CONFIG=$config" "KOKKOS_PREFIX=$prefix")
printf 'Machine: %s\nConfig: %s\nKokkos: %s\nJobs: %s\n' "$SYSTYPE" "$config" "$prefix" "$jobs"
# Site module functions are allowed to reference unset shell variables.
module -t list
set -u
if [[ $clean == 1 ]]; then
    make -C "$root/src" "${make_options[@]}" clean
fi
make -C "$root/src" -j"$jobs" "${make_options[@]}"
printf '\nBuilt: %s/src/GIZMO\nRuntime: use the same modules and export HSA_XNACK=1 in your job script.\n' "$root"
