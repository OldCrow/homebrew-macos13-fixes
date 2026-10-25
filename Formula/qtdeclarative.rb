# Patched for macOS 13 (Ventura) compatibility.
#
# qtdeclarative 6.12.0 fails to compile against the CLT's macOS 13.3 SDK:
#
#   qquickstyleconstants.mm: property 'secondarySystemFillColor' not found on object of type 'NSColor' (macOS 14 SDK)
#
# Qt 6.12 requires the macOS 15 SDK and uses macOS 14 API unconditionally.
# homebrew-core suppresses Qt's SDK check (-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON)
# and, with both CLT and Xcode installed, superenv picks the CLT SDK matching
# the host (13.3) unless the formula depends on Xcode. This override adds
# `depends_on xcode: :build`, so the build uses Xcode 15.2's 14.2 SDK, as the
# oldcrow/macos13-fixes qtbase override does. The deployment target stays 13:
# the patched QtAutoDetectHelpers.cmake installed by that qtbase propagates
# it to every submodule build. Otherwise identical to homebrew-core.
#
# Qt submodules require exact-version siblings (see AGENTS.md, "Version-lag
# hazard"): bump this formula in lockstep with homebrew-core's qtbase, or
# retire it.
#
# Bumped to 6.12.0_1 (2026-10-25) in lockstep with core's qtbase 6.12.0_1.
#
# Remove this formula once this machine leaves macOS 13, or homebrew-core
# qtdeclarative builds on it again.
class Qtdeclarative < Formula
  desc "QML, Qt Quick and several related modules"
  homepage "https://www.qt.io/"
  url "https://download.qt.io/official_releases/qt/6.12/6.12.0/submodules/qtdeclarative-everywhere-src-6.12.0.tar.xz"
  mirror "https://qt.mirror.constant.com/archive/qt/6.12/6.12.0/submodules/qtdeclarative-everywhere-src-6.12.0.tar.xz"
  mirror "https://mirrors.ukfast.co.uk/sites/qt.io/archive/qt/6.12/6.12.0/submodules/qtdeclarative-everywhere-src-6.12.0.tar.xz"
  sha256 "311f3a2603e1973bb59baef9dfa740a376de713157d4782ee043681e889c9260"
  license all_of: [
    { any_of: ["LGPL-3.0-only", "GPL-2.0-only", "GPL-3.0-only"] },
    { "GPL-3.0-only" => { with: "Qt-GPL-exception-1.0" } }, # qml
    "BSD-2-Clause", # masm
    "BSD-3-Clause", # *.cmake
  ]
  revision 1
  compatibility_version 1
  head "https://code.qt.io/qt/qtdeclarative.git", branch: "dev"

  livecheck do
    formula "qtbase"
  end

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "qtlanguageserver" => :build
  depends_on "qtshadertools" => :build
  depends_on "vulkan-headers" => :build

  depends_on "qtbase"
  depends_on "qtsvg"

  uses_from_macos "python" => :build

  on_macos do
    # Use Xcode's 14.2 SDK instead of the CLT's 13.3 SDK (see header comment).
    depends_on xcode: :build
  end

  conflicts_with "qt@5", because: "both link conflicting binaries"

  def install
    args = ["-DCMAKE_STAGING_PREFIX=#{prefix}"]
    args << "-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON" if OS.mac?

    system "cmake", "-S", ".", "-B", "build", "-G", "Ninja",
                    *args, *std_cmake_args(install_prefix: HOMEBREW_PREFIX, find_framework: "FIRST")
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    return unless OS.mac?

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink lib.glob("*.framework")

    # Remove non-executable file used for signing app
    rm(bin/"qml.entitlements")
  end

  test do
    # https://github.com/qt/qtdeclarative/blob/dev/tests/auto/qml/qqmlapplicationengine/testapp/immediateQuit.qml
    (testpath/"immediateQuit.qml").write <<~QML
      import QtQml
      import QtQuick
      QtObject {
        Component.onCompleted: {
          console.log("End: " + Qt.application.arguments[1]);
          Qt.quit()
        }
      }
    QML

    ENV["LC_ALL"] = "en_US.UTF-8"
    ENV["QT_QPA_PLATFORM"] = "minimal" if OS.linux?
    assert_match "qml: End: immediateQuit.qml", shell_output("#{bin}/qml immediateQuit.qml 2>&1")
  end
end
