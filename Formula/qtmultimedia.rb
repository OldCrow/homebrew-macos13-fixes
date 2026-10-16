# Patched for macOS 13 (Ventura) compatibility.
#
# qtmultimedia 6.12.0 fails to compile with Apple Clang 15 (clang-1500):
#
#   qdarwinformatsinfo.mm:174:63: error: reference to local binding
#   'containerName' declared in enclosing function enumerateDecoders
#
# The darwin plugin captures a structured binding in a lambda, which C++20
# (P1091R3) allows but Clang only implements from version 16. Xcode 15.2's
# Clang 15 rejects it. The inline patch copies the binding to a plain local
# before the lambdas. Otherwise identical to homebrew-core (which already
# depends on Xcode for the SDK and uses ENV.runtime_cpu_detection).
#
# Qt submodules require exact-version siblings (see AGENTS.md, "Version-lag
# hazard"): bump this formula in lockstep with homebrew-core's qtbase, or
# retire it.
#
# Remove this formula once this machine leaves macOS 13 / Apple Clang 15, or
# upstream stops capturing structured bindings in qdarwinformatsinfo.mm.
class Qtmultimedia < Formula
  desc "Provides APIs for playing back and recording audiovisual content"
  homepage "https://www.qt.io/"
  url "https://download.qt.io/official_releases/qt/6.12/6.12.0/submodules/qtmultimedia-everywhere-src-6.12.0.tar.xz"
  mirror "https://qt.mirror.constant.com/archive/qt/6.12/6.12.0/submodules/qtmultimedia-everywhere-src-6.12.0.tar.xz"
  mirror "https://mirrors.ukfast.co.uk/sites/qt.io/archive/qt/6.12/6.12.0/submodules/qtmultimedia-everywhere-src-6.12.0.tar.xz"
  sha256 "3143f53b64257ba2a0685c940f5dce476c75871ff86b516de45cfd54ea93a62d"
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

  livecheck do
    formula "qtbase"
  end

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
    depends_on "pipewire"
    depends_on "pulseaudio"
  end

  conflicts_with "qt@5", because: "both link conflicting binaries"

  # Apple Clang 15: no lambda capture of structured bindings (see header).
  patch :DATA

  def install
    # Allow -march options to be passed through, as Qt builds
    # arch-specific code with runtime detection of capabilities:
    # https://bugreports.qt.io/browse/QTBUG-113391
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
      system formula_opt_bin("qtbase")/"qmake", testpath/"test.pro"
      system "make"
      system "./test"
    end

    flags = shell_output("pkgconf --cflags --libs Qt6#{modules.join(" Qt6")}").chomp.split
    system ENV.cxx, "-std=c++17", "main.cpp", "-o", "test", *flags
    system "./test"
  end
end

__END__
--- a/src/plugins/multimedia/darwin/qdarwinformatsinfo.mm	2026-10-16 01:55:10
+++ b/src/plugins/multimedia/darwin/qdarwinformatsinfo.mm	2026-10-16 01:55:10
@@ -144,6 +144,10 @@
         for (auto [containerName, fileFormat, implicitCodec] : mediaContainerMap) {
             if (strcmp(filetype.UTF8String, containerName))
                 continue;
+
+            // Apple Clang 15 cannot capture a structured binding in a lambda
+            // (C++20 P1091R3, implemented in Clang 16); copy it first.
+            const char *const container = containerName;
 
             QList<VideoCodec> video;
             QList<AudioCodec> audio;
@@ -171,7 +175,7 @@
 
                     default: {
                         video = videoCodecMap | views::filter([&](const auto &record) {
-                            return isPlayableExtendedMIMEType(containerName, record.name);
+                            return isPlayableExtendedMIMEType(container, record.name);
                         }) | recordGetCodec
                                 | ranges::to<QList<VideoCodec>>();
                     }
@@ -179,7 +183,7 @@
                 }
 
                 audio = audioCodecMap | views::filter([&](const auto &record) {
-                    return isPlayableExtendedMIMEType(containerName, record.name);
+                    return isPlayableExtendedMIMEType(container, record.name);
                 }) | recordGetCodec
                         | ranges::to<QList<AudioCodec>>();
 
