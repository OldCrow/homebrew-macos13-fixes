# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# gnutls 3.8.13 fails to build on Apple Clang 15 (clang-1500) because
# CRAU_MAYBE_UNUSED in lib/crau/crau.h expands to [[__maybe_unused__]]
# (C23 attribute syntax) when __has_c_attribute(__maybe_unused__) is
# non-zero.  Apple Clang 15 then treats the stub definition:
#
#   void crau_data(struct crau_context_stack_st *stack [[__maybe_unused__]], ...)
#
# as a conflicting redeclaration of the earlier prototype (which has no
# attribute), producing 12 "conflicting types" errors and a build failure.
#
# The upstream homebrew-core formula guards against this only for
# clang_build_version <= 1400 (Monterey/Xcode 14); Ventura ships with
# clang-1500 and has no pre-built bottle, so it always hits this path.
#
# The inline patch moves __clang__ before __has_c_attribute so that
# Clang always uses __attribute__((__unused__)) — which does not affect
# the function's type signature — rather than [[__maybe_unused__]].
#
# Remove this formula once gnutls upstream or homebrew-core resolves the issue.
class Gnutls < Formula
  desc "GNU Transport Layer Security (TLS) Library"
  homepage "https://gnutls.org/"
  url "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz"
  mirror "https://www.mirrorservice.org/sites/ftp.gnupg.org/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz"
  sha256 "ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e"
  license all_of: ["LGPL-2.1-or-later", "GPL-3.0-only"]
  compatibility_version 1

  livecheck do
    url "https://www.gnutls.org/download.html"
    regex(/href=.*?gnutls[._-]v?(\d+(?:\.\d+)+)\.t/i)
    strategy :page_match do |page, regex|
      highest_version = page.scan(%r{href=.*?/gnutls/v?(\d+(?:\.\d+)+)/?["' >]}i)
                            .map { |match| match[0] }
                            .max_by { |v| Version.new(v) }
      next unless highest_version

      files_page = Homebrew::Livecheck::Strategy.page_content(
        "https://www.gnupg.org/ftp/gcrypt/gnutls/v#{highest_version}",
      )
      next if (files_page_content = files_page[:content]).blank?

      files_page_content.scan(regex).map { |match| match[0] }
    end
  end

  depends_on "pkgconf" => :build
  depends_on "texinfo" => :build
  depends_on "ca-certificates"
  depends_on "gmp"
  depends_on "libidn2"
  depends_on "libtasn1"
  depends_on "libunistring"
  depends_on "nettle"
  depends_on "p11-kit"
  depends_on "unbound"

  on_macos do
    depends_on "gettext"
  end

  on_linux do
    depends_on "zlib-ng-compat"
  end

  # Fix CRAU_MAYBE_UNUSED macro on Apple Clang 15 (clang-1500, Ventura).
  # __has_c_attribute(__maybe_unused__) is non-zero on this compiler, so the
  # macro expands to [[__maybe_unused__]].  Apple Clang 15 then rejects the
  # stub definitions as conflicting redeclarations of the plain prototypes.
  # Moving the __clang__ branch first forces the __attribute__((__unused__))
  # form, which does not alter the function type and compiles without error.
  patch :DATA

  def install
    args = %W[
      --disable-silent-rules
      --disable-static
      --sysconfdir=#{etc}
      --with-default-trust-store-file=#{pkgetc}/cert.pem
      --disable-heartbeat-support
      --with-p11-kit
    ]

    system "./configure", *args, *std_configure_args
    system "make", "install"

    inreplace [lib/"pkgconfig/gnutls.pc", lib/"pkgconfig/gnutls-dane.pc"], prefix, opt_prefix

    # certtool shadows the macOS certtool utility
    mv bin/"certtool", bin/"gnutls-certtool"
    mv man1/"certtool.1", man1/"gnutls-certtool.1"
  end

  def post_install
    rm(pkgetc/"cert.pem") if (pkgetc/"cert.pem").exist?
    pkgetc.install_symlink Formula["ca-certificates"].pkgetc/"cert.pem"
  end

  def caveats
    "Guile bindings are now in the `guile-gnutls` formula."
  end

  test do
    system bin/"gnutls-cli", "--version"
    assert_match "expired certificate", shell_output("#{bin}/gnutls-cli expired.badssl.com", 1)
  end
end
__END__
--- a/lib/crau/crau.h
+++ b/lib/crau/crau.h
@@ -251,13 +251,15 @@
 # else
 
 #  ifndef CRAU_MAYBE_UNUSED
-#   if defined(__has_c_attribute)
-#    if __has_c_attribute (__maybe_unused__)
-#     define CRAU_MAYBE_UNUSED [[__maybe_unused__]]
-#    endif
-#   elif defined(__GNUC__)
-#    define CRAU_MAYBE_UNUSED __attribute__((__unused__))
-#   endif
+#   if defined(__clang__)
+#    define CRAU_MAYBE_UNUSED __attribute__((__unused__))
+#   elif defined(__has_c_attribute) && __has_c_attribute (__maybe_unused__)
+#    define CRAU_MAYBE_UNUSED [[__maybe_unused__]]
+#   elif defined(__GNUC__)
+#    define CRAU_MAYBE_UNUSED __attribute__((__unused__))
+#   else
+#    define CRAU_MAYBE_UNUSED
+#   endif
 #  endif /* CRAU_MAYBE_UNUSED */
 
 void crau_push_context(struct crau_context_stack_st *stack CRAU_MAYBE_UNUSED,
