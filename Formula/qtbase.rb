# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# Qt 6.12.0 raised its minimum macOS deployment target to 14.4 (SDK 15,
# Xcode 16; see .cmake.conf QT_SUPPORTED_MIN_MACOS_VERSION). homebrew-core
# configures with -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON, so configure succeeds
# on Ventura and the build dies at the first hard 14.4 dependency:
#
#   src/corelib/thread/qfutex_mac_p.h:23:10: fatal error:
#     'os/os_sync_wait_on_address.h' file not found
#
# 6.12 replaced the __ulock_wait2/__ulock_wake syscalls that 6.11 used for
# QtCore's Darwin futex with the public os_sync_wait_on_address() API, which
# first shipped in the macOS 14.4 SDK. The 6.12 futex is also "always
# available" (QT_ALWAYS_USE_FUTEX, FutexAlwaysAvailable=true in the public
# qmutex.h), and the Mach-semaphore mutex fallback (qmutex_mac.cpp) was
# removed, so disabling the futex is not an option: the generic Unix fallback
# uses sem_init(), which macOS does not implement.
#
# The inline patch keeps 6.12's structure and, when the deployment target is
# below 14.4, provides the four os_sync_* functions as inline shims over
# __ulock_wait2/__ulock_wake (available since macOS 11) — the same syscalls
# libplatform's os_sync_* wrap and that Qt 6.11.x called directly. The
# SDK header is used unchanged on 14.4+ deployment targets. Verified on the
# macOS 13 SDK: both syscalls are exported by libsystem_kernel, timeouts
# report ETIMEDOUT, 32- and 64-bit waits/wakes work.
#
# Second problem, same cause: Qt 6.12 defaults CMAKE_OSX_DEPLOYMENT_TARGET to
# its 14.4 minimum when none is given, and homebrew-core passes none. Every
# object is then built with -mmacosx-version-min=14.4 (so the shim above would
# not even engage) and dyld refuses to load the result on macOS 13. The formula
# pins qtbase's deployment target to the running macOS, and the inline patch
# teaches the installed QtAutoDetectHelpers.cmake (used by every qt* submodule
# build via Qt6 BuildInternals) to honour $MACOSX_DEPLOYMENT_TARGET, or the
# host version when the host is older than Qt's minimum. homebrew-core's own
# qtbase pinned -DCMAKE_OSX_DEPLOYMENT_TARGET=min(host, sonoma) from 6.9.3
# through 6.11.2 and dropped it in 6.12.0.
#
# Third, 6.12.0 also dropped `depends_on xcode: :build`, so Homebrew now picks
# the CLT's 13.3 SDK over Xcode 15.2's 14.2 SDK, and the Cocoa/Darwin code
# uses macOS 14.0-14.2 SDK API unconditionally (NSView.clipsToBounds, EventKit
# full-access statuses, CALayer HDR flag). Restoring the Xcode build dependency
# gets the 14.2 SDK back. The 14.4-only ScreenCaptureKit screenshot path
# (SCScreenshotManager, getCurrentProcessShareableContentWithCompletionHandler:)
# is restored to the 6.11 CGDisplayCreateImageForRect code behind an SDK guard,
# and the EventKit/HDR guards are kept so the formula also builds with a 13 SDK.
#
# Not Ventura-specific: any macOS < 14.4 deployment target building Qt >= 6.12
# from source hits this. Qt dropped these targets deliberately, so an upstream
# fix is unlikely; the realistic exit is retiring Ventura.
#
# Qt submodules require exact-version siblings (see AGENTS.md, "Version-lag
# hazard"): bump this formula in lockstep with homebrew-core's qtbase, or
# retire it.
#
# Remove this formula once this machine leaves macOS 13, or homebrew-core
# qtbase builds on it again.
class Qtbase < Formula
  desc "Cross-platform application and UI framework"
  homepage "https://www.qt.io/"
  license all_of: [
    { any_of: ["LGPL-3.0-only", "GPL-2.0-only", "GPL-3.0-only"] },
    { "GPL-3.0-only" => { with: "Qt-GPL-exception-1.0" } }, # qmake
    "BSD-3-Clause", # *.cmake
    "GFDL-1.3-no-invariants-only", # *.qdoc
  ]
  compatibility_version 1
  head "https://code.qt.io/qt/qtbase.git", branch: "dev"

  stable do
    url "https://download.qt.io/official_releases/qt/6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz"
    mirror "https://qt.mirror.constant.com/archive/qt/6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz"
    mirror "https://mirrors.ukfast.co.uk/sites/qt.io/archive/qt/6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz"
    sha256 "a951bd163c7b80fc6b8c88d7668fb56abf91c152373e13c10666763238131307"

    # Backport to support md4c 0.6.0
    patch do
      url "https://github.com/qt/qtbase/commit/032643f99e090e0304ef935c2ee11c109d55c8a1.patch?full_index=1"
      sha256 "6870a711a6fb7ce6367f541e10ec9fe2785bd7d7484a2b1759b8d1f082a3f09f"
      type :backport
    end
  end

  # The first-party website doesn't make version information readily available,
  # so we check the `head` repository tags instead.
  livecheck do
    url :head
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any, arm64_golden_gate: "33f80fd31c736fd7596decb81317283c8b88a9be83e2581bc867813f6d0aefd2"
    sha256 cellar: :any, arm64_tahoe:       "8f2e7639fe17e5818af3f985f21987fd98228ea6ba9c06b9b2766c06629b0b92"
    sha256 cellar: :any, arm64_sequoia:     "05a650cc37066dedbb32b05355608e7902590d4bd3ff21649adce04275502d08"
    sha256 cellar: :any, arm64_linux:       "90894129c986e7372b6a8b85786086c83fc3f2875f8778f8bc9748f25bec26a2"
    sha256 cellar: :any, x86_64_linux:      "a057f2f917766dbfc6bedbe102e5215712fc74ff8e102333b9e42ae83d853806"
  end

  depends_on "cmake" => [:build, :test]
  depends_on "ninja" => :build
  depends_on "pkgconf" => [:build, :test]
  depends_on "vulkan-headers" => [:build, :test]

  depends_on "brotli"
  depends_on "dbus"
  depends_on "double-conversion"
  depends_on "freetype"
  depends_on "glib"
  depends_on "harfbuzz"
  depends_on "icu4c@78"
  depends_on "jpeg-turbo"
  depends_on "libb2"
  depends_on "libpng"
  depends_on "md4c"
  depends_on "openssl@4"
  depends_on "pcre2"
  depends_on "zstd"

  uses_from_macos "cups"
  uses_from_macos "krb5"
  uses_from_macos "sqlite"

  on_macos do
    depends_on "molten-vk" => :build
    # Build against Xcode's SDK (14.2 with Xcode 15.2) instead of the CLT's
    # 13.3 SDK, as core did through 6.11.2: the Cocoa plugin uses 14.0-14.2
    # SDK API unconditionally (NSView.clipsToBounds, EventKit full access, ...).
    # 14.4-only API is still handled by the inline patch.
    depends_on xcode: :build
  end

  on_linux do
    depends_on "fontconfig"
    depends_on "gdk-pixbuf"
    depends_on "gtk+3"
    depends_on "libdrm"
    depends_on "libice"
    depends_on "libsm"
    depends_on "libx11"
    depends_on "libxcb"
    depends_on "libxkbcommon"
    depends_on "mesa"
    depends_on "pango"
    depends_on "systemd"
    depends_on "wayland"
    depends_on "xcb-util-cursor"
    depends_on "xcb-util-image"
    depends_on "xcb-util-keysyms"
    depends_on "xcb-util-renderutil"
    depends_on "xcb-util-wm"
    depends_on "zlib-ng-compat"

    # https://github.com/orgs/Homebrew/discussions/6468#discussioncomment-14687372
    pour_bottle? only_if: :default_prefix
  end

  conflicts_with "qt@5", because: "both link conflicting binaries"

  # 1. Provide os_sync_wait_on_address() & co. via __ulock_wait2/__ulock_wake
  #    when the SDK lacks the header or the deployment target is below 14.4.
  # 2. QtAutoDetectHelpers.cmake: default the deployment target to
  #    $MACOSX_DEPLOYMENT_TARGET / the host version instead of Qt's 14.4
  #    minimum. The helper is installed with Qt6 BuildInternals, so this also
  #    covers every qt* submodule build (see header comment).
  # 3. qdarwinpermissionplugin_calendar.mm: EKAuthorizationStatusFullAccess /
  #    WriteOnly and the request*AccessToEvents methods are macOS 14 SDK API;
  #    restore Qt 6.11's EKAuthorizationStatusAuthorized /
  #    requestAccessToEntityType: path behind the SDK-version guard Qt itself
  #    used there.
  # 4. qcocoascreen.mm: screen grabbing moved to SCScreenshotManager and
  #    getCurrentProcessShareableContentWithCompletionHandler: (macOS 14.4 SDK),
  #    and reads CALayer.wantsExtendedDynamicRangeContent (14 SDK). Restore the
  #    6.11 CGDisplayCreateImageForRect grab and read the HDR flag via KVC when
  #    the SDK is older; the runtime @available(macOS 14) check already guards it.
  patch :DATA

  deny_network_access!

  def install
    # Allow -march options to be passed through, as Qt builds
    # arch-specific code with runtime detection of capabilities:
    # https://bugreports.qt.io/browse/QTBUG-113391
    ENV.runtime_cpu_detection

    # Remove bundled libraries
    rm_r(%w[
      src/3rdparty/double-conversion
      src/3rdparty/freetype
      src/3rdparty/harfbuzz-ng
      src/3rdparty/libjpeg
      src/3rdparty/libpng
      src/3rdparty/md4c
      src/3rdparty/pcre2
      src/3rdparty/sqlite
      src/3rdparty/xcb
      src/3rdparty/zlib
    ])

    # The install prefix is HOMEBREW_PREFIX so that modules can be installed in separate formulae
    cmake_args = std_cmake_args(install_prefix: HOMEBREW_PREFIX, find_framework: "FIRST") + %W[
      -DCMAKE_STAGING_PREFIX=#{prefix}
      -DINSTALL_ARCHDATADIR=share/qt
      -DINSTALL_DATADIR=share/qt
      -DINSTALL_EXAMPLESDIR=share/qt/examples
      -DINSTALL_MKSPECSDIR=share/qt/mkspecs
      -DINSTALL_TESTSDIR=share/qt/tests

      -DFEATURE_sql_mysql=OFF
      -DFEATURE_sql_odbc=OFF
      -DFEATURE_sql_psql=OFF

      -DFEATURE_openssl_linked=ON
      -DFEATURE_pkg_config=ON
      -DFEATURE_system_doubleconversion=ON
      -DFEATURE_system_freetype=ON
      -DFEATURE_system_harfbuzz=ON
      -DFEATURE_system_jpeg=ON
      -DFEATURE_system_libb2=ON
      -DFEATURE_system_pcre2=ON
      -DFEATURE_system_png=ON
      -DFEATURE_system_sqlite=ON
      -DFEATURE_system_zlib=ON
      -DQT_ALLOW_SYMLINK_IN_PATHS=ON
    ]

    cmake_args += if OS.mac?
      # Workaround to support relocatable installs in Homebrew's symlink directory structure.
      inreplace "cmake/QtQmakeHelpers.cmake",
                'set(QT_CONFIGURE_LIBLOCATION_TO_PREFIX_PATH "${from_lib_location_to_prefix}")',
                "set(QT_CONFIGURE_LIBLOCATION_TO_PREFIX_PATH \"#{HOMEBREW_PREFIX.relative_path_from(lib)}\")"

      # Qt 6.12 defaults CMAKE_OSX_DEPLOYMENT_TARGET to its 14.4 minimum; the
      # result would not load on this host. Pin it to the running macOS.
      %W[
        -DFEATURE_relocatable=ON
        -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON
        -DCMAKE_OSX_DEPLOYMENT_TARGET=#{MacOS.version}
      ]
    else
      # FIXME: Unable to use workaround for relocatable installs as paths are resolved relative
      # to absolutePath() rather than canonicalPath(). This can break based on order of RPATH.
      # https://github.com/qt/qtbase/blob/v6.9.2/src/corelib/global/qlibraryinfo.cpp#L304
      %w[
        -DFEATURE_relocatable=OFF
        -DFEATURE_xcb=ON
        -DFEATURE_system_xcb_xinput=ON
      ]
    end

    system "cmake", "-S", ".", "-B", "build", "-G", "Ninja", *cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink lib.glob("*.framework") if OS.mac?

    inreplace lib/"cmake/Qt6/qt.toolchain.cmake", "#{Superenv.shims_path}/", ""

    # CMake finds the `pkg-config` shim first, which Qt records in `qmodule.pri` (macOS only).
    inreplace share/"qt/mkspecs/qmodule.pri", "#{Superenv.shims_path}/", "#{HOMEBREW_PREFIX}/bin/" if OS.mac?

    # Install a qtversion.xml to ease integration with QtCreator
    # As far as we can tell, there is no ability to make the Qt buildsystem
    # generate this and it's in the Qt source tarball at all.
    # Multiple people on StackOverflow have asked for this and it's a pain
    # to add Qt to QtCreator (the official IDE) without it.
    # Given Qt upstream seems extremely unlikely to accept this: let's ship our
    # own version.
    # If you read this and you can eliminate it or upstream it: please do!
    # More context in https://github.com/Homebrew/homebrew-core/pull/124923
    (share/"qtcreator/QtProject/qtcreator/qtversion.xml").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE QtCreatorQtVersions>
      <qtcreator>
      <data>
        <variable>QtVersion.0</variable>
        <valuemap type="QVariantMap">
        <value type="int" key="Id">1</value>
        <value type="QString" key="Name">Qt %{Qt:Version} (#{HOMEBREW_PREFIX})</value>
        <value type="QString" key="QMakePath">#{opt_bin}/qmake</value>
        <value type="QString" key="QtVersion.Type">Qt4ProjectManager.QtVersion.Desktop</value>
        <value type="QString" key="autodetectionSource"></value>
        <value type="bool" key="isAutodetected">false</value>
        </valuemap>
      </data>
      <data>
        <variable>Version</variable>
        <value type="int">1</value>
      </data>
      </qtcreator>
    XML
  end

  def caveats
    <<~CAVEATS
      You can add Homebrew's Qt to QtCreator's "Qt Versions" in:
        Preferences > Qt Versions > Link with Qt...
      pressing "Choose..." and selecting as the Qt installation path:
        #{HOMEBREW_PREFIX}
    CAVEATS
  end

  test do
    modules = %w[Core Gui Widgets Sql Concurrent Network]
    vulkan_include = formula_opt_include("vulkan-headers")

    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 4.0)
      project(test VERSION 1.0.0 LANGUAGES CXX)
      set(CMAKE_AUTOMOC ON)
      set(CMAKE_AUTORCC ON)
      set(CMAKE_AUTOUIC ON)
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
      INCLUDEPATH += #{vulkan_include}
    QMAKE

    (testpath/"main.cpp").write <<~CPP
      #undef QT_NO_DEBUG
      #include <QCoreApplication>
      #include <QImageReader>
      #include <QtSql>
      #include <QVulkanInstance>

      int main(int argc, char *argv[]) {
        QCoreApplication app(argc, argv);
        Q_ASSERT(QSqlDatabase::isDriverAvailable("QSQLITE"));
        const auto &list = QImageReader::supportedImageFormats();
        QVulkanInstance inst;
        // See https://github.com/actions/runner-images/issues/1779
        // if (!inst.create())
        //   qFatal("Failed to create Vulkan instance: %d", inst.errorCode());
        for (const char* fmt : {"bmp", "cur", "gif", "ico", "jpeg", "jpg", "pbm", "pgm", "png", "ppm", "xbm", "xpm"}) {
          Q_ASSERT(list.contains(fmt));
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
      system bin/"qmake", testpath/"test.pro"
      system "make"
      system "./test"
    end

    # Test compiler and linker flags work separately
    cflags = shell_output("pkgconf --cflags Qt6#{modules.join(" Qt6")}").chomp.split
    ldflags = shell_output("pkgconf --libs Qt6#{modules.join(" Qt6")}").chomp.split
    system ENV.cxx, "-std=c++17", "-c", "main.cpp", "-o", "main.o", "-I#{vulkan_include}", *cflags
    system ENV.cxx, "main.o", "-o", "test", *ldflags
    system "./test"

    # Check QT_INSTALL_PREFIX is HOMEBREW_PREFIX to support split formulae
    assert_equal HOMEBREW_PREFIX.to_s, shell_output("#{bin}/qmake -query QT_INSTALL_PREFIX").chomp
  end
end

__END__
--- a/src/corelib/thread/qfutex_mac_p.h
+++ b/src/corelib/thread/qfutex_mac_p.h
@@ -20,7 +20,85 @@
 #include <qtsan_impl.h>
 #include <private/qglobal_p.h>
 
+#include <Availability.h>
+
+#if !__has_include(<os/os_sync_wait_on_address.h>) \
+    || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < 140400)
+// <os/os_sync_wait_on_address.h> is available from the macOS 14.4 SDK and its
+// functions may only be called unconditionally when deploying to 14.4 or
+// later (older SDKs lack the header; older deployment targets lack the symbols). For older deployment targets, emulate the same API on top of the
+// __ulock_wait2/__ulock_wake syscalls (available since macOS 11), which is
+// what Qt 6.11 used directly and what libplatform's os_sync_* wrap.
+#include <cerrno>
+#include <cstdint>
+
+extern "C" {
+// Source: https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.81.2/bsd/sys/ulock.h
+extern int __ulock_wait2(uint32_t operation, void *addr, uint64_t value,
+                         uint64_t timeout, uint64_t value2);
+extern int __ulock_wake(uint32_t operation, void *addr, uint64_t wake_value);
+}
+
+namespace {
+enum QtUlockOperation : uint32_t {
+    UL_COMPARE_AND_WAIT   = 1,
+    UL_COMPARE_AND_WAIT64 = 5,
+    ULF_WAKE_ALL          = 0x00000100,
+    ULF_NO_ERRNO          = 0x01000000,
+};
+
+enum : int {
+    OS_SYNC_WAIT_ON_ADDRESS_NONE = 0,
+    OS_SYNC_WAKE_BY_ADDRESS_NONE = 0,
+    OS_CLOCK_MACH_ABSOLUTE_TIME  = 32,
+};
+
+inline uint32_t qt_ulock_operation(size_t size)
+{
+    return ULF_NO_ERRNO | (size == 4 ? UL_COMPARE_AND_WAIT : UL_COMPARE_AND_WAIT64);
+}
+
+// ULF_NO_ERRNO makes the syscalls return -errno; convert to the os_sync_*
+// convention of returning -1 and setting errno.
+inline int qt_ulock_result(int r)
+{
+    if (r < 0) {
+        errno = -r;
+        return -1;
+    }
+    return r;
+}
+
+inline int os_sync_wait_on_address(void *addr, uint64_t value, size_t size, int)
+{
+    return qt_ulock_result(__ulock_wait2(qt_ulock_operation(size), addr, value, 0, 0));
+}
+
+inline int os_sync_wait_on_address_with_timeout(void *addr, uint64_t value, size_t size, int,
+                                                int, uint64_t timeout_ns)
+{
+    // A zero timeout means "forever" to __ulock_wait2; the deadline has
+    // already passed, so report a timeout instead of blocking.
+    if (timeout_ns == 0) {
+        errno = ETIMEDOUT;
+        return -1;
+    }
+    return qt_ulock_result(__ulock_wait2(qt_ulock_operation(size), addr, value, timeout_ns, 0));
+}
+
+inline int os_sync_wake_by_address_any(void *addr, size_t size, int)
+{
+    return qt_ulock_result(__ulock_wake(qt_ulock_operation(size), addr, 0));
+}
+
+inline int os_sync_wake_by_address_all(void *addr, size_t size, int)
+{
+    return qt_ulock_result(__ulock_wake(qt_ulock_operation(size) | ULF_WAKE_ALL, addr, 0));
+}
+} // unnamed namespace
+#else
 #include <os/os_sync_wait_on_address.h>
+#endif
 
 #define QT_ALWAYS_USE_FUTEX
 
--- a/cmake/QtAutoDetectHelpers.cmake
+++ b/cmake/QtAutoDetectHelpers.cmake
@@ -421,6 +421,23 @@
         if(NOT CMAKE_SYSTEM_NAME OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
             # macOS
             set(version "${QT_SUPPORTED_MIN_MACOS_VERSION}")
+            # Homebrew on macOS older than Qt's minimum: a Qt built here must at
+            # least run here. Honour MACOSX_DEPLOYMENT_TARGET from the
+            # environment (as CMake itself does), else fall back to the host
+            # version when it is older than Qt's minimum. Without this every
+            # module is built with -mmacosx-version-min=${QT_SUPPORTED_MIN_MACOS_VERSION}
+            # and dyld refuses to load the result on the build host.
+            if(DEFINED ENV{MACOSX_DEPLOYMENT_TARGET} AND NOT "$ENV{MACOSX_DEPLOYMENT_TARGET}" STREQUAL "")
+                set(version "$ENV{MACOSX_DEPLOYMENT_TARGET}")
+            elseif(CMAKE_HOST_APPLE)
+                execute_process(COMMAND sw_vers -productVersion
+                    OUTPUT_VARIABLE __qt_host_macos_version
+                    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
+                if(__qt_host_macos_version VERSION_LESS version)
+                    set(version "${__qt_host_macos_version}")
+                endif()
+                unset(__qt_host_macos_version)
+            endif()
         elseif(CMAKE_SYSTEM_NAME STREQUAL iOS)
             set(version "${QT_SUPPORTED_MIN_IOS_VERSION}")
         elseif(CMAKE_SYSTEM_NAME STREQUAL visionOS)
--- a/src/corelib/platform/darwin/qdarwinpermissionplugin_calendar.mm
+++ b/src/corelib/platform/darwin/qdarwinpermissionplugin_calendar.mm
@@ -20,12 +20,20 @@
     case EKAuthorizationStatusRestricted:
     case EKAuthorizationStatusDenied:
         return Qt::PermissionStatus::Denied;
+#if QT_MACOS_IOS_PLATFORM_SDK_EQUAL_OR_ABOVE(140000, 170000)
     case EKAuthorizationStatusFullAccess:
         return Qt::PermissionStatus::Granted;
     case EKAuthorizationStatusWriteOnly:
         return accessMode == QCalendarPermission::WriteOnly
             ? Qt::PermissionStatus::Granted
             : Qt::PermissionStatus::Denied;
+#else
+    // Pre-14/17 SDKs know neither FullAccess (same value as Authorized) nor
+    // WriteOnly; a WriteOnly status at runtime falls through to Denied below.
+    case EKAuthorizationStatusAuthorized:
+        Q_UNUSED(accessMode);
+        return Qt::PermissionStatus::Granted;
+#endif
     }
 
     qCWarning(lcPermissions) << "Unknown permission status" << status << "detected in" << self;
@@ -57,10 +65,15 @@
         callback([self checkPermission:permission]);
     };
 
+#if QT_MACOS_IOS_PLATFORM_SDK_EQUAL_OR_ABOVE(140000, 170000)
     if (accessMode == QCalendarPermission::WriteOnly)
         [self.eventStore requestWriteOnlyAccessToEventsWithCompletion:completionHandler];
     else
         [self.eventStore requestFullAccessToEventsWithCompletion:completionHandler];
+#else
+    Q_UNUSED(accessMode);
+    [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:completionHandler];
+#endif
 }
 
 @end
--- a/src/plugins/platforms/cocoa/qcocoascreen.mm
+++ b/src/plugins/platforms/cocoa/qcocoascreen.mm
@@ -521,8 +521,15 @@
 
             NSView *view = platformWindow->view();
 
+#if QT_APPLE_SDK_EQUAL_OR_ABOVE(MACOS(14))
             if (!view.layer.wantsExtendedDynamicRangeContent)
+                continue;
+#else
+            // CALayer.wantsExtendedDynamicRangeContent is declared in the
+            // macOS 14 SDK; the runtime check above guarantees it exists.
+            if (![[view.layer valueForKey:@"wantsExtendedDynamicRangeContent"] boolValue])
                 continue;
+#endif
 
             [view setNeedsDisplay:YES];
         }
@@ -610,6 +617,7 @@
         return {};
     }
 
+#if QT_APPLE_SDK_EQUAL_OR_ABOVE(MACOS(14, 4))
     auto grabFromDisplay = [](CGDirectDisplayID displayId, const QRect &grabRect) -> QPixmap {
         QMacAutoReleasePool pool;
 
@@ -702,6 +710,23 @@
         pixmap.setDevicePixelRatio(scale);
         return pixmap;
     };
+#else
+    // SCScreenshotManager and getCurrentProcessShareableContentWithCompletionHandler:
+    // need the macOS 14.4 SDK. Use the pre-6.12 CGDisplayCreateImageForRect path
+    // (deprecated in macOS 15, still available on 13) when building with an
+    // older SDK.
+    auto grabFromDisplay = [](CGDirectDisplayID displayId, const QRect &grabRect) -> QPixmap {
+        QCFType<CGImageRef> image = CGDisplayCreateImageForRect(displayId, grabRect.toCGRect());
+        const QCFType<CGColorSpaceRef> sRGBcolorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
+        if (CGImageGetColorSpace(image) != sRGBcolorSpace) {
+            qCDebug(lcQpaScreen) << "applying color correction for display" << displayId;
+            image = CGImageCreateCopyWithColorSpace(image, sRGBcolorSpace);
+        }
+        QPixmap pixmap = QPixmap::fromImage(qt_mac_toQImage(image));
+        pixmap.setDevicePixelRatio(QCocoaScreen::nativeScreenForDisplayId(displayId).backingScaleFactor);
+        return pixmap;
+    };
+#endif
 
     QRect grabRect = QRect(x, y, width, height);
     qCDebug(lcQpaScreen) << "input grab rect" << grabRect;
