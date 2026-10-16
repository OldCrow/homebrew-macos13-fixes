# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# ada 4.0.0 fails to compile with Homebrew LLVM 23's libc++:
#
#   include/ada/url_pattern_regex.h:32:40: error: no member named 'vector'
#     in namespace 'std'
#
# The headers use std::vector, std::optional and std::same_as without
# including <vector>, <optional> and <concepts>; they compiled only because
# older libc++ pulled them in transitively, and libc++ 23 stopped doing so.
# homebrew-core builds ada-url with Homebrew LLVM whenever
# clang_build_version <= 1500 (fails_with :clang, "Requires C++20 support"),
# which on Ventura means llvm 23.1.3, so the core formula always hits this
# here. Not Ventura-specific: any platform building 4.0.0 from source with
# libc++ 23 (or any strict standard library) fails the same way.
#
# Upstream fixed it after 4.0.0 in ada-url/ada@d85b80412f11 ("Add missing
# includes of standard library headers", #1292). That commit does not apply
# to 4.0.0 as-is (it also touches files that only exist on main), so the
# inline patch is that commit's hunks for files present in 4.0.0, plus
# hand-ported equivalents for the four files whose context moved.
#
# Remove this formula once homebrew-core ada-url moves to a release that
# contains d85b80412f11 (anything after 4.0.0).
class AdaUrl < Formula
  desc "WHATWG-compliant and fast URL parser written in modern C++"
  homepage "https://ada-url.com"
  url "https://github.com/ada-url/ada/archive/refs/tags/v4.0.0.tar.gz"
  sha256 "6d6c7ef7dd2e329320d34eb2ab29ccdc879ee3935af9dfb894a6640e58dc381d"
  license any_of: ["Apache-2.0", "MIT"]
  revision 1
  compatibility_version 2
  head "https://github.com/ada-url/ada.git", branch: "main"

  depends_on "cmake" => :build
  depends_on "cxxopts" => :build
  depends_on "fmt"
  depends_on "simdutf"

  uses_from_macos "python" => :build

  on_macos do
    depends_on "llvm" if DevelopmentTools.clang_build_version <= 1500
  end

  fails_with :clang do
    build 1500
    cause "Requires C++20 support"
  end

  fails_with :gcc do
    version "11"
    cause "Requires C++20"
  end

  # Backport of ada-url/ada@d85b80412f11: add the missing standard-library
  # includes (see header comment).
  patch :DATA

  deny_network_access!

  def install
    # ld: unknown options: --gc-sections
    if OS.mac? && DevelopmentTools.clang_build_version <= 1500
      inreplace "tools/cli/CMakeLists.txt", 'target_link_options(adaparse PRIVATE "-Wl,--gc-sections")', ""
    end
    # Do not statically link to libstdc++
    inreplace "tools/cli/CMakeLists.txt", 'target_link_options(adaparse PRIVATE "-static-libstdc++")', "" if OS.linux?

    # CPM/FetchContent args are to allow using our newer `simdutf`
    args = %W[
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DBUILD_SHARED_LIBS=ON
      -DADA_TOOLS=ON
      -DADA_USE_SIMDUTF=ON
      -DCPM_USE_LOCAL_PACKAGES=ON
      -DHOMEBREW_ALLOW_FETCHCONTENT=ON
      -DFETCHCONTENT_FULLY_DISCONNECTED=ON
    ]

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    (testpath/"test.cpp").write <<~CPP
      #include "ada.h"
      #include <iostream>

      int main(int , char *[]) {
        auto url = ada::parse<ada::url_aggregator>("https://www.github.com/ada-url/ada");
        url->set_protocol("http");
        std::cout << url->get_protocol() << std::endl;
        return EXIT_SUCCESS;
      }
    CPP

    system ENV.cxx, "test.cpp", "-std=c++20", "-I#{include}", "-L#{lib}", "-lada", "-o", "test"
    assert_equal "http:", shell_output("./test").chomp

    require "pty"
    output_log = testpath/"output.log"
    test_url = "http://www.google.com/bal?a==11#fddfds"
    pid = PTY.spawn(bin/"adaparse", "-d", test_url, [:out, :err] => output_log.to_s).last
    Process.wait(pid)
    assert_match "search_start 25", output_log.read
  end
end

__END__
diff --color -ruN a/include/ada/character_sets-inl.h b/include/ada/character_sets-inl.h
--- a/include/ada/character_sets-inl.h
+++ b/include/ada/character_sets-inl.h
@@ -9,6 +9,8 @@
 
 #include "ada/character_sets.h"
 
+#include <cstdint>
+
 /**
  * These functions are not part of our public API and may
  * change at any time.
diff --color -ruN a/include/ada/checkers-inl.h b/include/ada/checkers-inl.h
--- a/include/ada/checkers-inl.h
+++ b/include/ada/checkers-inl.h
@@ -6,6 +6,7 @@
 #define ADA_CHECKERS_INL_H
 
 #include <bit>
+#include <cstddef>
 #include <cstdint>
 #include <cstring>
 #include <string_view>
diff --color -ruN a/include/ada/checkers.h b/include/ada/checkers.h
--- a/include/ada/checkers.h
+++ b/include/ada/checkers.h
@@ -7,6 +7,7 @@
 
 #include "ada/common_defs.h"
 
+#include <cstdint>
 #include <cstring>
 #include <string_view>
 
diff --color -ruN a/include/ada/encoding_type.h b/include/ada/encoding_type.h
--- a/include/ada/encoding_type.h
+++ b/include/ada/encoding_type.h
@@ -11,6 +11,7 @@
 
 #include "ada/common_defs.h"
 #include <string>
+#include <string_view>
 
 namespace ada {
 
diff --color -ruN a/include/ada/expected.h b/include/ada/expected.h
--- a/include/ada/expected.h
+++ b/include/ada/expected.h
@@ -25,8 +25,10 @@
 #define TL_EXPECTED_VERSION_MINOR 1
 #define TL_EXPECTED_VERSION_PATCH 0
 
+#include <cstddef>
 #include <exception>
 #include <functional>
+#include <initializer_list>
 #include <type_traits>
 #include <utility>
 
diff --color -ruN a/include/ada/helpers.h b/include/ada/helpers.h
--- a/include/ada/helpers.h
+++ b/include/ada/helpers.h
@@ -8,11 +8,15 @@
 #include "ada/common_defs.h"
 #include "ada/url_base.h"
 
+#include <cstddef>
+#include <cstdint>
+#include <optional>
 #include <string>
 #include <string_view>
-#include <optional>
+#include <utility>
 
 #if ADA_DEVELOPMENT_CHECKS
+#include <cstdlib>
 #include <iostream>
 #endif  // ADA_DEVELOPMENT_CHECKS
 
diff --color -ruN a/include/ada/implementation-inl.h b/include/ada/implementation-inl.h
--- a/include/ada/implementation-inl.h
+++ b/include/ada/implementation-inl.h
@@ -9,8 +9,13 @@
 #include "ada/expected.h"
 #include "ada/implementation.h"
 
-#include <variant>
+#include <cstddef>
+#include <span>
+#include <string>
 #include <string_view>
+#include <utility>
+#include <variant>
+#include <vector>
 
 namespace ada {
 
diff --color -ruN a/include/ada/implementation.h b/include/ada/implementation.h
--- a/include/ada/implementation.h
+++ b/include/ada/implementation.h
@@ -14,6 +14,8 @@
 #include <string>
 #include <string_view>
 #include <optional>
+#include <cstdint>
+#include <variant>
 
 #include "ada/url.h"
 #include "ada/common_defs.h"
diff --color -ruN a/include/ada/parser-inl.h b/include/ada/parser-inl.h
--- a/include/ada/parser-inl.h
+++ b/include/ada/parser-inl.h
@@ -9,8 +9,10 @@
 #include "ada/url_pattern_helpers.h"
 #include "ada/parser.h"
 
+#include <cstdint>
 #include <string>
 #include <string_view>
+#include <utility>
 #include <variant>
 
 namespace ada::parser {
diff --color -ruN a/include/ada/parser.h b/include/ada/parser.h
--- a/include/ada/parser.h
+++ b/include/ada/parser.h
@@ -11,6 +11,8 @@
 #ifndef ADA_PARSER_H
 #define ADA_PARSER_H
 
+#include <cstddef>
+#include <cstdint>
 #include <string_view>
 #include <variant>
 
diff --color -ruN a/include/ada/scheme-inl.h b/include/ada/scheme-inl.h
--- a/include/ada/scheme-inl.h
+++ b/include/ada/scheme-inl.h
@@ -7,6 +7,10 @@
 
 #include "ada/scheme.h"
 
+#include <cstddef>
+#include <cstdint>
+#include <string_view>
+
 namespace ada::scheme {
 
 /**
diff --color -ruN a/include/ada/scheme.h b/include/ada/scheme.h
--- a/include/ada/scheme.h
+++ b/include/ada/scheme.h
@@ -13,7 +13,9 @@
 
 #include "ada/common_defs.h"
 
+#include <cstdint>
 #include <string>
+#include <string_view>
 
 /**
  * @namespace ada::scheme
diff --color -ruN a/include/ada/serializers.h b/include/ada/serializers.h
--- a/include/ada/serializers.h
+++ b/include/ada/serializers.h
@@ -11,6 +11,8 @@
 #include "ada/common_defs.h"
 
 #include <array>
+#include <cstddef>
+#include <cstdint>
 #include <string>
 
 /**
diff --color -ruN a/include/ada/unicode-inl.h b/include/ada/unicode-inl.h
--- a/include/ada/unicode-inl.h
+++ b/include/ada/unicode-inl.h
@@ -7,6 +7,11 @@
 #include "ada/unicode.h"
 #include "ada/character_sets.h"
 
+#include <cstddef>
+#include <cstdint>
+#include <cstring>
+#include <string_view>
+
 /**
  * Unicode operations. These functions are not part of our public API and may
  * change at any time.
diff --color -ruN a/include/ada/unicode.h b/include/ada/unicode.h
--- a/include/ada/unicode.h
+++ b/include/ada/unicode.h
@@ -8,9 +8,11 @@
 #include "ada/common_defs.h"
 #include "ada/ada_idna.h"
 
+#include <cstddef>
+#include <cstdint>
+#include <optional>
 #include <string>
 #include <string_view>
-#include <optional>
 
 /**
  * Unicode operations. These functions are not part of our public API and may
diff --color -ruN a/include/ada/url-inl.h b/include/ada/url-inl.h
--- a/include/ada/url-inl.h
+++ b/include/ada/url-inl.h
@@ -9,9 +9,14 @@
 #include "ada/url_components.h"
 
 #include <charconv>
+#include <cstdint>
 #include <cstring>
 #include <optional>
+#include <ostream>
 #include <string>
+#include <string_view>
+#include <system_error>
+#include <utility>
 #if ADA_REGULAR_VISUAL_STUDIO
 #include <intrin.h>
 #endif  // ADA_REGULAR_VISUAL_STUDIO
diff --color -ruN a/include/ada/url.h b/include/ada/url.h
--- a/include/ada/url.h
+++ b/include/ada/url.h
@@ -12,6 +12,8 @@
 #define ADA_URL_H
 
 #include <algorithm>
+#include <cstddef>
+#include <cstdint>
 #include <optional>
 #include <ostream>
 #include <string>
diff --color -ruN a/include/ada/url_aggregator-inl.h b/include/ada/url_aggregator-inl.h
--- a/include/ada/url_aggregator-inl.h
+++ b/include/ada/url_aggregator-inl.h
@@ -14,6 +14,9 @@
 #include "ada/log.h"
 
 #include <charconv>
+#include <cstdint>
+#include <string>
+#include <system_error>
 #include <ostream>
 #include <string_view>
 
diff --color -ruN a/include/ada/url_aggregator.h b/include/ada/url_aggregator.h
--- a/include/ada/url_aggregator.h
+++ b/include/ada/url_aggregator.h
@@ -11,6 +11,8 @@
 #ifndef ADA_URL_AGGREGATOR_H
 #define ADA_URL_AGGREGATOR_H
 
+#include <cstddef>
+#include <cstdint>
 #include <ostream>
 #include <string>
 #include <string_view>
diff --color -ruN a/include/ada/url_base-inl.h b/include/ada/url_base-inl.h
--- a/include/ada/url_base-inl.h
+++ b/include/ada/url_base-inl.h
@@ -9,6 +9,7 @@
 #include "ada/checkers.h"
 #include "ada/url.h"
 
+#include <cstdint>
 #include <string>
 #if ADA_REGULAR_VISUAL_STUDIO
 #include <intrin.h>
diff --color -ruN a/include/ada/url_base.h b/include/ada/url_base.h
--- a/include/ada/url_base.h
+++ b/include/ada/url_base.h
@@ -12,6 +12,8 @@
 #include "ada/common_defs.h"
 #include "ada/scheme.h"
 
+#include <cstddef>
+#include <cstdint>
 #include <string>
 #include <string_view>
 
diff --color -ruN a/include/ada/url_components-inl.h b/include/ada/url_components-inl.h
--- a/include/ada/url_components-inl.h
+++ b/include/ada/url_components-inl.h
@@ -7,6 +7,8 @@
 
 #include "ada/url_components.h"
 
+#include <cstdint>
+
 namespace ada {
 
 [[nodiscard]] constexpr bool url_components::check_offset_consistency()
diff --color -ruN a/include/ada/url_components.h b/include/ada/url_components.h
--- a/include/ada/url_components.h
+++ b/include/ada/url_components.h
@@ -9,6 +9,9 @@
 #ifndef ADA_URL_COMPONENTS_H
 #define ADA_URL_COMPONENTS_H
 
+#include <cstdint>
+#include <string>
+
 namespace ada {
 
 /**
diff --color -ruN a/include/ada/url_ip-inl.h b/include/ada/url_ip-inl.h
--- a/include/ada/url_ip-inl.h
+++ b/include/ada/url_ip-inl.h
@@ -11,6 +11,7 @@
 #include "ada/common_defs.h"
 
 #include <array>
+#include <cstddef>
 #include <cstdint>
 
 #if defined(ADA_AVX512)
diff --color -ruN a/include/ada/url_pattern-inl.h b/include/ada/url_pattern-inl.h
--- a/include/ada/url_pattern-inl.h
+++ b/include/ada/url_pattern-inl.h
@@ -10,8 +10,13 @@
 #include "ada/url_pattern.h"
 
 #include <algorithm>
+#include <cstddef>
+#include <optional>
+#include <string>
 #include <string_view>
 #include <utility>
+#include <variant>
+#include <vector>
 
 #if ADA_INCLUDE_URL_PATTERN
 namespace ada {
diff --color -ruN a/include/ada/url_pattern.h b/include/ada/url_pattern.h
--- a/include/ada/url_pattern.h
+++ b/include/ada/url_pattern.h
@@ -17,10 +17,13 @@
 #include "ada/parser.h"
 #include "ada/url_pattern_init.h"
 
+#include <cstdint>
+#include <optional>
 #include <ostream>
 #include <string>
 #include <string_view>
 #include <unordered_map>
+#include <utility>
 #include <variant>
 #include <vector>
 
diff --color -ruN a/include/ada/url_pattern_helpers-inl.h b/include/ada/url_pattern_helpers-inl.h
--- a/include/ada/url_pattern_helpers-inl.h
+++ b/include/ada/url_pattern_helpers-inl.h
@@ -5,8 +5,13 @@
 #ifndef ADA_URL_PATTERN_HELPERS_INL_H
 #define ADA_URL_PATTERN_HELPERS_INL_H
 
+#include <cstddef>
+#include <cstdint>
 #include <optional>
+#include <string>
 #include <string_view>
+#include <utility>
+#include <vector>
 
 #include "ada/common_defs.h"
 #include "ada/expected.h"
diff --color -ruN a/include/ada/url_pattern_helpers.h b/include/ada/url_pattern_helpers.h
--- a/include/ada/url_pattern_helpers.h
+++ b/include/ada/url_pattern_helpers.h
@@ -10,6 +10,11 @@
 #include "ada/url_pattern.h"
 
 #include <string>
+#include <cstddef>
+#include <cstdint>
+#include <optional>
+#include <string_view>
+#include <utility>
 #include <tuple>
 #include <vector>
 
diff --color -ruN a/include/ada/url_pattern_init.h b/include/ada/url_pattern_init.h
--- a/include/ada/url_pattern_init.h
+++ b/include/ada/url_pattern_init.h
@@ -8,10 +8,12 @@
 #include "ada/expected.h"
 #include "ada/errors.h"
 
-#include <string_view>
-#include <string>
-#include <optional>
+#include <concepts>
+#include <cstdint>
 #include <iostream>
+#include <optional>
+#include <string>
+#include <string_view>
 
 #if ADA_TESTING
 #include <iostream>
diff --color -ruN a/include/ada/url_pattern_regex.h b/include/ada/url_pattern_regex.h
--- a/include/ada/url_pattern_regex.h
+++ b/include/ada/url_pattern_regex.h
@@ -5,8 +5,11 @@
 #ifndef ADA_URL_PATTERN_REGEX_H
 #define ADA_URL_PATTERN_REGEX_H
 
+#include <concepts>
+#include <optional>
 #include <string>
 #include <string_view>
+#include <vector>
 
 #ifdef ADA_USE_UNSAFE_STD_REGEX_PROVIDER
 #include <regex>
diff --color -ruN a/include/ada/url_search_params-inl.h b/include/ada/url_search_params-inl.h
--- a/include/ada/url_search_params-inl.h
+++ b/include/ada/url_search_params-inl.h
@@ -10,7 +10,9 @@
 #include "ada/url_search_params.h"
 
 #include <algorithm>
+#include <cstddef>
 #include <cstdint>
+#include <iterator>
 #include <optional>
 #include <ranges>
 #include <string>
diff --color -ruN a/include/ada/url_search_params.h b/include/ada/url_search_params.h
--- a/include/ada/url_search_params.h
+++ b/include/ada/url_search_params.h
@@ -11,9 +11,11 @@
 #ifndef ADA_URL_SEARCH_PARAMS_H
 #define ADA_URL_SEARCH_PARAMS_H
 
+#include <cstddef>
 #include <optional>
 #include <string>
 #include <string_view>
+#include <utility>
 #include <vector>
 
 namespace ada {
diff --color -ruN a/src/checkers.cpp b/src/checkers.cpp
--- a/src/checkers.cpp
+++ b/src/checkers.cpp
@@ -5,6 +5,8 @@
 
 #include <algorithm>
 #include <array>
+#include <cstddef>
+#include <cstdint>
 #include <string_view>
 
 namespace ada::checkers {
diff --color -ruN a/src/helpers.cpp b/src/helpers.cpp
--- a/src/helpers.cpp
+++ b/src/helpers.cpp
@@ -1,6 +1,11 @@
+#include <array>
 #include <cstdint>
 #include <cstring>
+#include <optional>
 #include <sstream>
+#include <string>
+#include <string_view>
+#include <utility>
 
 #include "ada/checkers-inl.h"
 #include "ada/common_defs.h"
diff --color -ruN a/src/implementation.cpp b/src/implementation.cpp
--- a/src/implementation.cpp
+++ b/src/implementation.cpp
@@ -1,6 +1,8 @@
 #include "ada/implementation-inl.h"
 
 #include <atomic>
+#include <cstdint>
+#include <string>
 #include <limits>
 #include <optional>
 #include <string_view>
diff --color -ruN a/src/parser.cpp b/src/parser.cpp
--- a/src/parser.cpp
+++ b/src/parser.cpp
@@ -3,7 +3,11 @@
 #include <array>
 #include <cstring>
 #include <limits>
+#include <optional>
 #include <ranges>
+#include <string>
+#include <string_view>
+#include <utility>
 
 #include "ada/character_sets-inl.h"
 #include "ada/checkers-inl.h"
diff --color -ruN a/src/unicode.cpp b/src/unicode.cpp
--- a/src/unicode.cpp
+++ b/src/unicode.cpp
@@ -11,7 +11,13 @@
 
 #include <algorithm>
 #include <array>
+#include <cstdint>
 #include <cstring>
+#include <iterator>
+#include <optional>
+#include <string>
+#include <string_view>
+#include <utility>
 #if ADA_SSSE3
 #include <tmmintrin.h>
 #elif ADA_NEON
diff --color -ruN a/src/url.cpp b/src/url.cpp
--- a/src/url.cpp
+++ b/src/url.cpp
@@ -8,12 +8,15 @@
 
 #include <algorithm>
 #include <array>
+#include <cstddef>
 #include <cstdint>
 #include <iterator>
 #include <numeric>
+#include <optional>
 #include <ranges>
 #include <string>
 #include <string_view>
+#include <utility>
 
 namespace ada {
 
diff --color -ruN a/src/url_aggregator.cpp b/src/url_aggregator.cpp
--- a/src/url_aggregator.cpp
+++ b/src/url_aggregator.cpp
@@ -10,13 +10,16 @@
 #include "ada/url_aggregator-inl.h"
 #include "ada/url_ip-inl.h"
 
+#include <algorithm>
 #include <array>
 #include <cstdint>
 #include <cstring>
 #include <iterator>
+#include <optional>
 #include <ranges>
 #include <string>
 #include <string_view>
+#include <utility>
 
 namespace {
 
diff --color -ruN a/src/url_pattern.cpp b/src/url_pattern.cpp
--- a/src/url_pattern.cpp
+++ b/src/url_pattern.cpp
@@ -5,6 +5,8 @@
 #include <algorithm>
 #include <optional>
 #include <string>
+#include <string_view>
+#include <utility>
 
 namespace ada {
 
diff --color -ruN a/src/url_pattern_helpers.cpp b/src/url_pattern_helpers.cpp
--- a/src/url_pattern_helpers.cpp
+++ b/src/url_pattern_helpers.cpp
@@ -4,9 +4,16 @@
 #include <algorithm>
 #include <array>
 #include <charconv>
+#include <cstddef>
+#include <cstdint>
 #include <optional>
 #include <ranges>
 #include <string>
+#include <string_view>
+#include <system_error>
+#include <tuple>
+#include <utility>
+#include <vector>
 
 #include "ada/character_sets.h"
 #include "ada/checkers.h"
diff --color -ruN a/src/url_pattern_regex.cpp b/src/url_pattern_regex.cpp
--- a/src/url_pattern_regex.cpp
+++ b/src/url_pattern_regex.cpp
@@ -2,6 +2,15 @@
 
 #include "ada/url_pattern_regex.h"
 
+#ifdef ADA_USE_UNSAFE_STD_REGEX_PROVIDER
+#include <cstddef>
+#include <optional>
+#include <regex>
+#include <string>
+#include <string_view>
+#include <vector>
+#endif  // ADA_USE_UNSAFE_STD_REGEX_PROVIDER
+
 namespace ada::url_pattern_regex {
 
 #ifdef ADA_USE_UNSAFE_STD_REGEX_PROVIDER
