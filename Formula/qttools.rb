# qttools 6.11.1: not a macOS/Clang issue -- homebrew-core's litehtml formula
# was bumped to 0.10 (PR litehtml/litehtml#415 changed background_paint from a
# single struct to a std::vector and switched int coordinates to a float
# `pixel_t`). qttools' bundled qlitehtml wrapper (src/assistant/qlitehtml) was
# not updated for that API change, so building against the external system
# litehtml (as homebrew-core's formula forces via
# -DQLITEHTML_USE_SYSTEM_LITEHTML=ON, after deleting the vendored copy) fails
# with "no member named 'background_paint'" / narrowing-conversion errors.
# Fix: keep the vendored src/assistant/qlitehtml/src/3rdparty/litehtml copy
# (which matches the API qlitehtml expects) instead of forcing the newer
# external litehtml.
# Remove this formula once qttools' qlitehtml wrapper is updated for
# litehtml >= 0.10, or homebrew-core pins/patches around the mismatch.
class Qttools < Formula
  desc "Facilitate the design, development, testing and deployment of applications"
  homepage "https://www.qt.io/"
  url "https://download.qt.io/official_releases/qt/6.11/6.11.1/submodules/qttools-everywhere-src-6.11.1.tar.xz"
  mirror "https://qt.mirror.constant.com/archive/qt/6.11/6.11.1/submodules/qttools-everywhere-src-6.11.1.tar.xz"
  mirror "https://mirrors.ukfast.co.uk/sites/qt.io/archive/qt/6.11/6.11.1/submodules/qttools-everywhere-src-6.11.1.tar.xz"
  sha256 "8e61835a679c93fa9c6065b142353c2071ba68e297898937c32a03777fcaf50d"
  license all_of: [
    { any_of: ["LGPL-3.0-only", "GPL-2.0-only", "GPL-3.0-only"] },
    { "GPL-3.0-only" => { with: "Qt-GPL-exception-1.0" } },
    "BSD-3-Clause", # *.cmake
    "BSL-1.0", # bundled catch2
  ]
  compatibility_version 1
  head "https://code.qt.io/qt/qttools.git", branch: "dev"

  depends_on "cmake" => [:build, :test]
  depends_on "ninja" => :build
  depends_on "vulkan-headers" => :build

  depends_on "qtbase"
  depends_on "qtdeclarative"
  depends_on "zstd"

  on_macos do
    depends_on "gumbo-parser"
  end

  conflicts_with "qt@5", because: "both link conflicting binaries"

  def install
    # See header comment: keep the bundled litehtml so qlitehtml builds
    # against the API it was actually written for.

    # Modify Assistant path as we manually move `*.app` bundles from `bin` to `prefix`.
    # This fixes invocation of Assistant via the Help menu of apps like Designer and
    # Linguist as they originally relied on Assistant.app being in `bin`.
    inreplace "src/shared/helpclient/assistantclient.cpp", '"Assistant.app/Contents/MacOS/Assistant"', '"Assistant"'

    # We disable clang feature to avoid linkage to `llvm`. This is how we have always
    # built on macOS and it prevents complicating `llvm` version bumps on Linux.
    args = %W[
      -DFEATURE_clang=OFF
      -DCMAKE_STAGING_PREFIX=#{prefix}
    ]
    args << "-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON" if OS.mac?

    system "cmake", "-S", ".", "-B", "build", "-G", "Ninja",
                    *args, *std_cmake_args(install_prefix: HOMEBREW_PREFIX, find_framework: "FIRST")
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    return unless OS.mac?

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink lib.glob("*.framework")

    bin.glob("*.app") do |app|
      libexec.install app
      bin.write_exec_script libexec/app.basename/"Contents/MacOS"/app.stem
    end
  end

  test do
    # Based on https://doc.qt.io/qt-6/qtlinguist-hellotr-example.html
    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 4.0)
      project(hellotr LANGUAGES CXX)
      find_package(Qt6 REQUIRED COMPONENTS Core LinguistTools)
      qt_standard_project_setup(I18N_TRANSLATED_LANGUAGES la)
      qt_add_executable(hellotr main.cpp)
      qt6_add_translations(hellotr QM_FILES_OUTPUT_VARIABLE qm_files)
      target_link_libraries(hellotr PUBLIC Qt::Core)
    CMAKE

    (testpath/"main.cpp").write <<~CPP
      #include <iostream>
      #include <QTranslator>

      int main(void) {
        QTranslator translator;
        Q_UNUSED(translator.load("hellotr_la"));
        std::cout << translator.translate("main", "Hello world!").toStdString();
        return 0;
      }
    CPP

    (testpath/"hellotr_la.ts").write <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE TS>
      <TS/>
    XML

    ENV["LC_ALL"] = "en_US.UTF-8"
    system "cmake", "."
    system "cmake", "--build", ".", "--target", "update_translations"
    inreplace "hellotr_la.ts", '<translation type="unfinished"></translation>',
                               "<translation>Orbis, te saluto!</translation>"
    system "cmake", "--build", "."
    assert_equal "Orbis, te saluto!", shell_output("./hellotr")
  end
end
