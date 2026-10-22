"""Check Makefile dependency selection without a GPU, CMake or installed Kokkos.

Run: python3 dev/test_kokkos_config.py
The fixture libraries are placeholders: these checks validate flags, not linkage.
"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class InstalledKokkosTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gizmo-kokkos-")
        self.addCleanup(self.temp.cleanup)
        self.work = pathlib.Path(self.temp.name)
        self.prefix = self.work / "installed"
        self.makefile = self.work / "Makefile"
        self.makefile.write_text(
            "CXX := mpicxx -std=c++17\n"
            "GPU_CXX := old-nvcc\n"
            "GPU_CFLAGS := old-device-flags\n"
            "GPU_LDFLAGS := old-link-flags\n"
            "KOKKOS_PATH := /site/kokkos\n"
            "KOKKOS_CPPFLAGS := -I/site/kokkos/include\n"
            "KOKKOS_CXXFLAGS := -arch=sm_80 -I/site/mpi/include\n"
            "KOKKOS_LDFLAGS := -L/site/kokkos/lib64 -Wl,-rpath,/site/kokkos/lib64 "
            "-L/site/cuda/lib -L/site/cuda/stubs -Wl,-rpath,/site/cuda/lib\n"
            f"include {ROOT}/config/kokkos/installed.mk\n"
            ".PHONY: show\nshow:\n"
            "\t@printf '%s\\n' 'prefix=$(KOKKOS_PATH)' 'cpp=$(KOKKOS_CPPFLAGS)' "
            "'compiler=$(GPU_CXX)' 'flags=$(GPU_CFLAGS)' 'link=$(GPU_LDFLAGS)' "
            "'libs=$(KOKKOS_LIBS)' 'backend=$(GIZMO_KOKKOS_BACKEND)'\n"
        )

    def install(self, backend, libdir="lib", metadata=None):
        (self.prefix / "include").mkdir(parents=True)
        (self.prefix / "include/KokkosCore_config.h").write_text(
            "#define KOKKOS_ENABLE_SERIAL\n"
            + (f"#define KOKKOS_ENABLE_{backend}\n" if backend != "SERIAL" else "")
        )
        (self.prefix / libdir).mkdir()
        (self.prefix / libdir / "libkokkoscore.a").touch()
        (self.prefix / "bin").mkdir()
        (self.prefix / "bin/nvcc_wrapper").touch()
        if metadata:
            (self.prefix / "share/gizmo").mkdir(parents=True)
            (self.prefix / "share/gizmo/kokkos.mk").write_text(metadata)

    def query(self, prefix=True):
        cmd = ["make", "--no-print-directory", "-f", str(self.makefile), "show"]
        if prefix:
            cmd.append(f"KOKKOS_PREFIX={self.prefix}")
        return subprocess.run(cmd, text=True, capture_output=True, cwd=self.work)

    def values(self, prefix=True):
        result = self.query(prefix)
        self.assertEqual(result.returncode, 0, result.stderr)
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def test_no_override_preserves_machine_settings(self):
        values = self.values(False)
        self.assertEqual(values["compiler"], "old-nvcc")
        self.assertEqual(values["flags"], "old-device-flags")
        self.assertEqual(values["link"], "old-link-flags")
        self.assertEqual(values["prefix"], "/site/kokkos")

    def test_cuda_replaces_kokkos_paths_and_preserves_cuda_and_mpi(self):
        self.install("CUDA", "lib64")
        values = self.values()
        self.assertEqual(values["backend"], "CUDA")
        self.assertEqual(values["compiler"], f"{self.prefix}/bin/nvcc_wrapper --std=c++17")
        self.assertIn(f"-I{self.prefix}/include", values["flags"])
        self.assertIn("-I/site/mpi/include", values["flags"])
        self.assertIn("-arch=sm_80", values["flags"])
        self.assertNotIn("/site/kokkos", values["link"])
        self.assertIn("-L/site/cuda/stubs", values["link"])
        self.assertIn(f"-Wl,-rpath,{self.prefix}/lib64", values["link"])
        self.assertIn("-lcudart -lcuda", values["libs"])

    def test_source_profile_changes_architecture_flags(self):
        self.install("CUDA", metadata="GIZMO_KOKKOS_PROFILE := cuda-h100-release\n"
                     "GIZMO_KOKKOS_DEVICE_FLAGS := --expt-extended-lambda -arch=sm_90\n")
        values = self.values()
        self.assertIn("-arch=sm_90", values["flags"])
        self.assertNotIn("-arch=sm_80", values["flags"])
        self.assertIn("-I/site/mpi/include", values["flags"])

    def test_hip_selects_hipcc(self):
        self.install("HIP", metadata="GIZMO_KOKKOS_PROFILE := hip-mi250-release\n"
                     "GIZMO_KOKKOS_DEVICE_FLAGS := --offload-arch=gfx90a:xnack+\n")
        values = self.values()
        self.assertEqual(values["compiler"], "hipcc --std=c++17")
        self.assertIn("--offload-arch=gfx90a:xnack+", values["flags"])
        self.assertNotIn("-lcudart", values["libs"])

    def test_cpu_uses_host_compiler_without_cuda_flags(self):
        for backend in ("SERIAL", "OPENMP"):
            with self.subTest(backend=backend):
                # Use a new fixture path for each backend.
                self.prefix = self.work / backend
                self.install(backend)
                values = self.values()
                self.assertEqual(values["compiler"], "mpicxx -std=c++17")
                self.assertNotIn("-arch=", values["flags"])
                self.assertNotIn("-lcudart", values["libs"])

    def test_bad_prefix_and_missing_wrapper_fail_early(self):
        self.assertNotEqual(self.query().returncode, 0)
        self.install("CUDA")
        (self.prefix / "bin/nvcc_wrapper").unlink()
        result = self.query()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nvcc_wrapper", result.stderr)


if __name__ == "__main__":
    unittest.main()
