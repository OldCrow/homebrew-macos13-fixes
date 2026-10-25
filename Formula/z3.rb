# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
# Two independent compiler/stdlib issues prevent z3 5.3.1 from building:
#
# 1. P0960R3 (parenthesized aggregate initialization) in obj_hashtable.h.
#    z3 5.3.1 no longer does this inside obj_hashtable.h, but expr2var.cpp
#    still constructs the key_data typedef with parentheses:
#
#      m_mapping.push_back(key_value(n, v));
#
#    and symbol_table.h gained its own aggregate key_data, built with
#    `key_data dummy(key)` in find() and insert().
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
# Core's own answer (5.0.0+) is `fails_with :clang` on Ventura or older, which
# makes Homebrew build with its LLVM clang. That path fails here before
# compiling anything: z3's LTO probe runs with -flto=thin and CMake finds no
# llvm-ar through superenv ("CMAKE_CXX_COMPILER_AR-NOTFOUND"). Core does
# not build Ventura, so it never sees this. This override keeps Apple Clang
# 15 and drops that block; the two fixes above are all it needs.
# 5.3.1 uses std::format in 10 files (was 29 call sites in 4.16.0), still
# only with bare {} placeholders, so the polyfill is unchanged.
#
# Remove this formula once homebrew-core ships a fix or a Ventura bottle.
class Z3 < Formula
  desc "High-performance theorem prover"
  homepage "https://github.com/Z3Prover/z3"
  url "https://github.com/Z3Prover/z3/archive/refs/tags/z3-5.3.1.tar.gz"
  sha256 "c007089dd8d92298d2a7d14105b14e8dddfbb540062ce471c3111e0741edd8da"
  license "MIT"
  compatibility_version 5
  head "https://github.com/Z3Prover/z3.git", branch: "master"

  livecheck do
    url :stable
    regex(/z3[._-]v?(\d+(?:\.\d+)+)/i)
    strategy :github_latest
  end

  depends_on "cmake" => :build
  # Has Python bindings but are supplementary to the main library
  # which does not need Python.
  depends_on "python@3.15" => [:build, :test]

  fails_with :gcc do
    version "12"
    cause "Requires C++20 std::format, https://gcc.gnu.org/gcc-13/changes.html#libstdcxx"
  end

  deny_network_access!

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
    # z3 5.3.1 (10 files, all simple error messages).
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
              "        Value m_value;\n        " \
              "key_data() = default;\n        " \
              "key_data(Key * k) : m_key(k) {}\n        " \
              "key_data(Key * k, Value const & v) : m_key(k), m_value(v) {}\n        " \
              "key_data(Key * k, Value && v) : m_key(k), m_value(std::move(v)) {}\n        " \
              "Value const & get_value()"
    end

    # 5.x adds a second parenthesized-aggregate site: symbol_table<T>::key_data
    # (symbol_table.h) is still a plain aggregate and is constructed with
    # `key_data dummy(key)` in find() and insert(). Brace-initialize it.
    inreplace "src/util/symbol_table.h", "key_data dummy(key);", "key_data dummy{key};"

    # euf_egraph.h: update_record's anonymous-struct union member m_th is an
    # aggregate initialized with parentheses in two mem-initializers.
    inreplace "src/ast/euf/euf_egraph.h" do |s|
      # theory_id/theory_var are int; the bitfields are unsigned. Braces forbid
      # the implicit narrowing the parentheses allowed, so cast explicitly.
      s.gsub! "m_th(id, v) {}", "m_th{static_cast<unsigned>(id), static_cast<unsigned>(v)} {}"
      s.gsub! "m_th(th_id) {}", "m_th{th_id} {}"
    end

    # smt component: three more aggregates built with parentheses.
    inreplace "src/smt/smt_conflict_resolution.h", "m_pair(lhs, rhs) {}", "m_pair{lhs, rhs} {}"
    inreplace "src/smt/theory_finite_set_size.cpp", "in lit(p, v == l_true);", "in lit{p, v == l_true};"
    # `reach` is allocated through z3's alloc() macro, which spells T(args...),
    # so give it a constructor instead of touching the call sites.
    inreplace "src/smt/theory_array_full.cpp",
              "            enode* m_store = nullptr;\n        };",
              "            enode* m_store = nullptr;\n            " \
              "reach(enode* r, reach* p = nullptr, enode* s = nullptr) : " \
              "m_root(r), m_parent(p), m_store(s) {}\n        };"

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
