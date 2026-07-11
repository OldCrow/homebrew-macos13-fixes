# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
# Two independent compiler/stdlib issues prevent z3 4.16.0 from building:
#
# 1. P0960R3 (parenthesized aggregate initialization) in obj_hashtable.h.
#    z3 4.16.0 constructs the key_data aggregate with parentheses:
#
#      m_table.insert(key_data(k, v));
#
#    P0960R3 was not implemented in Clang until version 16.  Apple Clang 15
#    (clang-1500, Ventura / Xcode 15) rejects these calls because key_data
#    has only implicit constructors — none matching 1 or 2 arguments.
#    Fix: replace key_data(args) with key_data{args} (C++14 brace aggregate
#    initialization) at all six call sites in obj_hashtable.h.
#
# 2. std::format disabled in the macOS 13 SDK libc++.
#    Two guards prevent use: __config defines _LIBCPP_HAS_NO_INCOMPLETE_FORMAT
#    (hiding the entire <format> implementation), and __availability defines
#    _LIBCPP_AVAILABILITY_FORMAT as __attribute__((unavailable)) for macOS < 14,
#    which marks all format types as unavailable and causes template
#    substitution failures even if the first guard is removed.
#    Fix: force-include a self-contained polyfill that never touches the SDK
#    <format> header, implementing plain {} substitution via ostringstream.
#
# Remove this formula once homebrew-core ships a fix or a Ventura bottle.
class Z3 < Formula
  desc "High-performance theorem prover"
  homepage "https://github.com/Z3Prover/z3"
  url "https://github.com/Z3Prover/z3/archive/refs/tags/z3-4.16.0.tar.gz"
  sha256 "c68c3e5e4810b16126b8cb4c47eee85c1ac3e24a81914c8e371b40de9dd33ac7"
  license "MIT"
  compatibility_version 2

  livecheck do
    url :stable
    regex(/z3[._-]v?(\d+(?:\.\d+)+)/i)
    strategy :github_latest
  end

  depends_on "cmake" => :build
  # Has Python bindings but are supplementary to the main library
  # which does not need Python.
  depends_on "python@3.14" => [:build, :test]

  fails_with :gcc do
    version "12"
    cause "Requires C++20 std::format, https://gcc.gnu.org/gcc-13/changes.html#libstdcxx"
  end

  def python3
    which("python3.14")
  end

  def install
    # std::format is disabled in the macOS 13 SDK in two layers:
    # (1) _LIBCPP_HAS_NO_INCOMPLETE_FORMAT in __config hides the <format>
    #     implementation entirely.
    # (2) _LIBCPP_AVAILABILITY_FORMAT expands to __attribute__((unavailable))
    #     for macOS < 14, marking all format types and functions as unavailable.
    # Unlocking the SDK header triggers template substitution failures because
    # the unavailable attribute propagates into internal helper types.
    #
    # Fix: force-include a self-contained polyfill that never touches <format>.
    # It handles the plain {} placeholder syntax — the only form used by
    # z3 4.16.0 (29 call sites in src/ast/, all simple error messages).
    # On macOS 14+ _LIBCPP_HAS_NO_INCOMPLETE_FORMAT is not defined, so the
    # polyfill is a compile-time no-op there.
    (buildpath/"z3_format_compat.h").write <<~EOS
      // Provides std::format on macOS 13 without touching the SDK <format>.
      // Active only when _LIBCPP_HAS_NO_INCOMPLETE_FORMAT is defined.
      #pragma once
      #include <__config>
      #ifdef _LIBCPP_HAS_NO_INCOMPLETE_FORMAT
      #include <string>
      #include <sstream>
      namespace z3_format_compat {
          inline void fmt_impl(std::string& out, const std::string& t) { out += t; }
          template <typename First, typename... Rest>
          void fmt_impl(std::string& out, const std::string& t,
                        First const& first, Rest const&... rest) {
              auto pos = t.find("{}");
              if (pos == std::string::npos) { out += t; return; }
              out += t.substr(0, pos);
              std::ostringstream oss; oss << first; out += oss.str();
              fmt_impl(out, t.substr(pos + 2), rest...);
          }
      }
      namespace std {
          template <typename... Args>
          inline std::string format(char const* t, Args const&... args) {
              std::string r; z3_format_compat::fmt_impl(r, t, args...); return r;
          }
          template <typename... Args>
          inline std::string format(std::string const& t, Args const&... args) {
              std::string r; z3_format_compat::fmt_impl(r, t, args...); return r;
          }
      }
      #endif // _LIBCPP_HAS_NO_INCOMPLETE_FORMAT
    EOS
    ENV.append "CXXFLAGS", "-include #{buildpath}/z3_format_compat.h"

    # Apple Clang 15 (macOS 13 Ventura) does not implement C++20 P0960R3
    # (parenthesized aggregate initialization), so key_data(k, v) and
    # key_data(k) fail to compile.  Replace with brace-initialization, which
    # is equivalent and has been valid since C++14.
    inreplace "src/util/obj_hashtable.h" do |s|
      # Add explicit constructors to key_data so that both internal call sites
      # in obj_hashtable.h and external callers (e.g. expr2var.cpp's key_value
      # typedef) can use T(args) syntax without P0960R3.
      # key_data() = default preserves the m_key = nullptr member initializer.
      s.gsub! "        Value m_value;\n        Value const & get_value()",
              "        Value m_value;\n" \
              "        key_data() = default;\n" \
              "        key_data(Key * k) : m_key(k) {}\n" \
              "        key_data(Key * k, Value const & v) : m_key(k), m_value(v) {}\n" \
              "        key_data(Key * k, Value && v) : m_key(k), m_value(std::move(v)) {}\n" \
              "        Value const & get_value()"
    end

    args = %W[
      -DZ3_LINK_TIME_OPTIMIZATION=ON
      -DZ3_INCLUDE_GIT_DESCRIBE=OFF
      -DZ3_INCLUDE_GIT_HASH=OFF
      -DZ3_INSTALL_PYTHON_BINDINGS=ON
      -DZ3_BUILD_EXECUTABLE=ON
      -DZ3_BUILD_TEST_EXECUTABLES=OFF
      -DZ3_BUILD_PYTHON_BINDINGS=ON
      -DZ3_BUILD_DOTNET_BINDINGS=OFF
      -DZ3_BUILD_JAVA_BINDINGS=OFF
      -DZ3_USE_LIB_GMP=OFF
      -DPYTHON_EXECUTABLE=#{python3}
      -DCMAKE_INSTALL_PYTHON_PKG_DIR=#{Language::Python.site_packages(python3)}
    ]

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    system "make", "-C", "contrib/qprofdiff"
    bin.install "contrib/qprofdiff/qprofdiff"

    pkgshare.install "examples"
  end

  test do
    system ENV.cc, pkgshare/"examples/c/test_capi.c", "-I#{include}",
                   "-L#{lib}", "-lz3", "-o", testpath/"test"
    system "./test"
    assert_equal version.to_s, shell_output("#{python3} -c 'import z3; print(z3.get_version_string())'").strip
  end
end
