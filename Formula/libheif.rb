# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# libheif 1.22.0 adds a new struct in include/libheif/heif_properties.h:
#
#   struct heif_bad_pixel { uint32_t row; uint32_t column; };   // line 322
#
# but the function prototype on line 338 uses the type without the
# `struct` tag:
#
#   const heif_bad_pixel* bad_pixels
#
# In C++ this is valid: struct names are first-class type names.  In C
# (C89/C99/C11/C17) a struct without a typedef must always be prefixed
# with `struct`.  imagemagick's coders/heic.c is a plain C translation
# unit, so Apple Clang 15 rejects the include:
#
#   heif_properties.h:338:56: error: must use 'struct' tag to refer
#   to type 'heif_bad_pixel'
#
# The inline patch adds `typedef struct heif_bad_pixel heif_bad_pixel;`
# immediately after the struct definition, making the bare identifier
# valid in both C and C++.
#
# Remove this formula once libheif upstream adds the typedef or
# homebrew-core ships a Ventura bottle.
class Libheif < Formula
  desc "ISO/IEC 23008-12:2017 HEIF file format decoder and encoder"
  homepage "https://www.libde265.org/"
  url "https://github.com/strukturag/libheif/releases/download/v1.22.0/libheif-1.22.0.tar.gz"
  sha256 "8bd20cfa3201997b8f63266cddfabea2e1481467d7f992e6a2595e0bec691fc2"
  license "LGPL-3.0-or-later"
  compatibility_version 1

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build

  depends_on "aom"
  depends_on "jpeg-turbo"
  depends_on "libde265"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "webp"
  depends_on "x265"

  # heif_properties.h line 338 uses `heif_bad_pixel*` without the `struct`
  # tag.  Valid in C++ but a hard error in C.  Add the missing typedef.
  patch :DATA

  def install
    args = %W[
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DPLUGIN_DIRECTORY=#{HOMEBREW_PREFIX}/lib/libheif
      -DPLUGIN_INSTALL_DIRECTORY=#{lib}/libheif
      -DWITH_DAV1D=OFF
      -DWITH_EXAMPLE_HEIF_VIEW=OFF
      -DWITH_GDK_PIXBUF=OFF
      -DWITH_OpenH264_DECODER=OFF
      -DWITH_RAV1E=OFF
      -DWITH_SvtEnc=OFF
      -DWITH_X264=OFF
    ]

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    pkgshare.install "examples/example.heic"
    pkgshare.install "examples/example.avif"

    system "cmake", "-S", ".", "-B", "static", *args, *std_cmake_args, "-DBUILD_SHARED_LIBS=OFF"
    system "cmake", "--build", "static"
    lib.install "static/libheif/libheif.a"

    # Avoid rebuilding dependents that hard-code the prefix.
    inreplace lib/"pkgconfig/libheif.pc", prefix, opt_prefix
  end

  def caveats
    "Additional codecs can be enabled by `brew install libheif-plugins`"
  end

  test do
    output = "File contains 2 images"
    example = pkgshare/"example.heic"
    exout = testpath/"exampleheic.jpg"

    assert_match output, shell_output("#{bin}/heif-convert #{example} #{exout}")
    assert_path_exists testpath/"exampleheic-1.jpg"
    assert_path_exists testpath/"exampleheic-2.jpg"

    output = "File contains 1 image"
    example = pkgshare/"example.avif"
    exout = testpath/"exampleavif.jpg"

    assert_match output, shell_output("#{bin}/heif-convert #{example} #{exout}")
    assert_path_exists testpath/"exampleavif.jpg"
  end
end
__END__
--- a/libheif/api/libheif/heif_properties.h
+++ b/libheif/api/libheif/heif_properties.h
@@ -319,7 +319,8 @@

 // --- Sensor bad pixels map (ISO 23001-17, Section 6.1.7)

 struct heif_bad_pixel { uint32_t row; uint32_t column; };
+typedef struct heif_bad_pixel heif_bad_pixel;

 // Add a sensor bad pixels map to an image.
 // component_indices: array of component indices this map applies to (may be NULL if num_component_indices == 0,
