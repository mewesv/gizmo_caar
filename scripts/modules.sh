#!/bin/bash

module restore

module load cpe/26.03 PrgEnv-amd craype-accel-amd-gfx90a amd/7.2.0 rocm/7.2.0

module load cray-hdf5-parallel

module load cmake cray-python emacs

module load gsl/2.8 cray-fftw

module unload darshan-runtime

module -t list

export LD_LIBRARY_PATH=${CRAY_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}
