# qtmultimedia 6.11.1: Homebrew's superenv build shim strips all `-march=`
# flags unless the formula opts in via `ENV.runtime_cpu_detection`. Qt's SIMD
# dispatch source (e.g. qvideoframeconversionhelper_avx2.cpp) is compiled
# per-file for AVX2 but relies on the global `-march=haswell` optflag to
# actually enable the AVX/AVX2 target features. With the flag stripped, Apple
# Clang 15 rejects the file's always_inline AVX2 intrinsics ("requires target
# feature 'avx', but would be inlined into function ... that is compiled
# without support for 'avx'"). Fix: enable ENV.runtime_cpu_detection so
# superenv preserves `-march=`. No Ventura bottle exists, so this always
# builds from source and always hits the failure.
# Remove this formula once homebrew-core enables runtime_cpu_detection for
# qtmultimedia (or ships a Ventura bottle).
class Qtmultimedia < Formula
  desc "Provides APIs for playing back and recording audiovisual content"
  homepage "https://www.qt.io/"
  url "https://download.qt.io/official_releases/qt/6.11/6.11.1/submodules/qtmultimedia-everywhere-src-6.11.1.tar.xz"
  mirror "https://qt.mirror.constant.com/archive/qt/6.11/6.11.1/submodules/qtmultimedia-everywhere-src-6.11.1.tar.xz"
  mirror "https://mirrors.ukfast.co.uk/sites/qt.io/archive/qt/6.11/6.11.1/submodules/qtmultimedia-everywhere-src-6.11.1.tar.xz"
  sha256 "390f8e52ddee3aca5c4de7eead900c84c4fa61ff6d1f0ebea9c7543365c09b0a"
  license all_of: [
    { any_of: ["LGPL-3.0-only", "GPL-2.0-only", "GPL-3.0-only"] },
    { all_of: ["MPL-2.0", "BSD-3-Clause"] }, # bundled eigen
    "Apache-2.0",   # bundled resonance-audio
    "BSD-3-Clause", # bundled pffft; *.cmake
    "GPL-3.0-only", # Qt6MultimediaTestLib
    "MIT",          # bundled signalsmith-stretch (Linux)
  ]
  compatibility_version 1
  head "https://code.qt.io/qt/qtmultimedia.git", branch: "dev"

  depends_on "cmake" => [:build, :test]
  depends_on "ninja" => :build
  depends_on "qtshadertools" => :build
  depends_on "vulkan-headers" => :build
  depends_on "pkgconf" => :test
  depends_on "qtbase"
  depends_on "qtdeclarative"
  depends_on "qtquick3d"

  on_macos do
    depends_on macos: :ventura
    depends_on "qtshadertools"
  end

  on_ventura do
    depends_on xcode: ["15.0", :build] # for `@available(macOS 14)`
  end

  on_linux do
    depends_on "ffmpeg"
    depends_on "glib"
    depends_on "gstreamer"
    depends_on "libva"
    depends_on "libx11"
    depends_on "libxext"
    depends_on "libxrandr"
    depends_on "mesa"
    depends_on "pulseaudio"
  end

  conflicts_with "qt@5", because: "both link conflicting binaries"

  def install
    # See header comment: without this, superenv strips -march=haswell and
    # breaks the AVX2 SIMD dispatch files on Apple Clang 15.
    ENV.runtime_cpu_detection

    args = ["-DCMAKE_STAGING_PREFIX=#{prefix}"]
    if OS.mac?
      args << "-DQT_FEATURE_ffmpeg=OFF"
      args << "-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON"
    end

    system "cmake", "-S", ".", "-B", "build", "-G", "Ninja",
                    *args, *std_cmake_args(install_prefix: HOMEBREW_PREFIX, find_framework: "FIRST")
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink lib.glob("*.framework") if OS.mac?
  end

  test do
    modules = %w[Core Multimedia]

    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 4.0)
      project(test VERSION 1.0.0 LANGUAGES CXX)
      find_package(Qt6 REQUIRED COMPONENTS #{modules.join(" ")})
      add_executable(test main.cpp)
      target_link_libraries(test PRIVATE Qt6::#{modules.join(" Qt6::")})
    CMAKE

    (testpath/"test.pro").write <<~QMAKE
      QT      += #{modules.join(" ").downcase}
      TARGET   = test
      CONFIG  += console
      CONFIG  -= app_bundle
      TEMPLATE = app
      SOURCES += main.cpp
    QMAKE

    (testpath/"main.cpp").write <<~CPP
      #include <QCoreApplication>
      #include <QAudioDevice>
      #include <QMediaDevices>
      #include <QTextStream>

      int main(int argc, char *argv[]) {
        QCoreApplication app(argc, argv);
        QTextStream out(stdout);
        for(const QAudioDevice &device : QMediaDevices::audioInputs()) {
          out << "ID: " << device.id() << Qt::endl;
        }
        return 0;
      }
    CPP

    ENV["LC_ALL"] = "en_US.UTF-8"
    ENV["QT_QPA_PLATFORM"] = "minimal" if OS.linux? && ENV["HOMEBREW_GITHUB_ACTIONS"]

    system "cmake", "-S", ".", "-B", "cmake"
    system "cmake", "--build", "cmake"
    system "./cmake/test"

    ENV.delete "CPATH" if OS.mac?
    mkdir "qmake" do
      system Formula["qtbase"].bin/"qmake", testpath/"test.pro"
      system "make"
      system "./test"
    end

    flags = shell_output("pkgconf --cflags --libs Qt6#{modules.join(" Qt6")}").chomp.split
    system ENV.cxx, "-std=c++17", "main.cpp", "-o", "test", *flags
    system "./test"
  end
end
