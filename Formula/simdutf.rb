# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# node 26.x builds V8 against the shared simdutf, and V8 calls
# simdutf::atomic_binary_to_base64 / atomic_base64_to_binary_safe. simdutf
# compiles those functions only when SIMDUTF_ATOMIC_REF is set
# (__cpp_lib_atomic_ref). node's formula builds with Homebrew LLVM whenever
# clang_build_version <= 1699 (fails_with :clang), whose libc++ has
# std::atomic_ref; homebrew-core simdutf builds with Apple Clang 15 and the
# macOS 13 SDK libc++, which lacks it. The two sides then disagree:
#
#   - V8 compiles calls to the atomic API, but libsimdutf exports none of it,
#     so linking node's mksnapshot fails with undefined
#     simdutf::atomic_* symbols.
#   - simdutf's own base64 benchmark fails to compile under Apple Clang 15
#     because it guards the atomic calls with the C++ version instead of
#     SIMDUTF_ATOMIC_REF (https://github.com/simdutf/simdutf/issues/1045).
#
# Fix: build simdutf with the same toolchain rule as node, so both see the
# same libc++. With LLVM's libc++ SIMDUTF_ATOMIC_REF is set, the atomic API is
# exported, and the benchmark compiles unpatched. atomic_ref is header-only;
# the library still links the system libc++, as node does.
#
# Not Ventura-specific: any macOS with clang_build_version <= 1699 and no
# simdutf bottle (Intel macOS, Sonoma) hits the same mismatch.
#
# Bumped to 9.3.2_1 on icu4c@79 (2026-10-25) to stay in lockstep with core:
# node 26.12.1_1 and ada-url 4.0.0_1 are built against simdutf 9.3 and
# icu4c@79. Re-copy the core formula on every bump and re-apply the
# toolchain rule below.
#
# Remove this formula once homebrew-core simdutf builds with the same
# toolchain as node, or ships a bottle for this platform.
class Simdutf < Formula
  desc "Unicode conversion routines, fast"
  homepage "https://simdutf.github.io/simdutf/"
  url "https://github.com/simdutf/simdutf/archive/refs/tags/v9.3.2.tar.gz"
  sha256 "d92a0a4ce216dcebf18af20fed7ea7279fa535683f790fdaeed39827a234f567"
  license any_of: ["Apache-2.0", "MIT"]
  revision 1
  compatibility_version 7
  head "https://github.com/simdutf/simdutf.git", branch: "master"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on "aklomp-base64" => :build
  depends_on "cmake" => :build
  depends_on "icu4c@79"

  uses_from_macos "python" => :build

  on_macos do
    depends_on "llvm" => :build if DevelopmentTools.clang_build_version <= 1699
  end

  # Match node's toolchain: V8 in node calls simdutf's atomic API, which is
  # compiled in only when libc++ provides std::atomic_ref.
  fails_with :clang do
    build 1699
    cause "atomic API needs std::atomic_ref; must match node's toolchain"
  end

  deny_network_access!

  def install
    # C++20 is needed by `node`
    args = %W[
      -DBUILD_SHARED_LIBS=ON
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
      -DCPM_LOCAL_PACKAGES_ONLY=ON
      -DPython3_EXECUTABLE=#{which("python3")}
      -DSIMDUTF_BENCHMARKS=ON
      -DSIMDUTF_CXX_STANDARD=20
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    bin.install "build/benchmarks/benchmark" => "sutf-benchmark"
  end

  test do
    system bin/"sutf-benchmark", "--random-utf8", "10240", "-I", "100"
  end
end
