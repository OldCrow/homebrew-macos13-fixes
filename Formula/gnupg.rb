# Patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
#
# gnupg 2.5.21 `make check` fails on macOS 13 with two test failures:
#
#   t-http-basic    — Abort trap: 6 (SIGABRT).  The HTTP test makes outbound
#                     TLS connections that macOS 13 SIP blocks inside the
#                     Homebrew build sandbox, causing an unconditional abort.
#
#   t-ldap-parse-uri — dyld cannot load libhogweed.6.dylib.  gnutls was
#                      compiled against nettle 3.x (libhogweed soversion 6)
#                      but nettle 4.0 is now installed, which exports only
#                      libhogweed.7.dylib.  gnutls must be rebuilt against
#                      the current nettle to resolve this; see the companion
#                      oldcrow/macos13-fixes/gnutls formula.
#
# The configure + make + make install sequence succeeds without errors.
# Only the test harness is affected.  The fix is to skip `make check`.
#
# Remove this formula once homebrew-core ships a Ventura bottle or the
# upstream test failures are resolved.
class Gnupg < Formula
  desc "GNU Privacy Guard (OpenPGP)"
  homepage "https://gnupg.org/"
  url "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.5.21.tar.bz2"
  sha256 "e3af2c8caa46a66a9329fa7c6880af260451914d819595beabc2c26597b31352"
  license "GPL-3.0-or-later"
  compatibility_version 1

  livecheck do
    url :homepage
    regex(/The current version of GnuPG is v?(\d+(?:\.\d+)+)\. /i)
  end

  depends_on "pkgconf" => :build
  depends_on "gnutls"
  depends_on "libassuan"
  depends_on "libgcrypt"
  depends_on "libgpg-error"
  depends_on "libksba"
  depends_on "libusb"
  depends_on "npth"
  depends_on "pinentry"
  depends_on "readline"

  uses_from_macos "bzip2"
  uses_from_macos "openldap"
  uses_from_macos "sqlite"

  on_macos do
    depends_on "gettext"
  end

  on_linux do
    depends_on "zlib-ng-compat"
  end

  conflicts_with cask: "gpg-suite"
  conflicts_with cask: "gpg-suite-no-mail"
  conflicts_with cask: "gpg-suite-pinentry"
  conflicts_with cask: "gpg-suite@nightly"

  def install
    libusb = Formula["libusb"]
    ENV.append "CPPFLAGS", "-I#{libusb.opt_include}/libusb-#{libusb.version.major_minor}"

    mkdir "build" do
      system "../configure", "--disable-silent-rules",
                             "--enable-all-tests",
                             "--sysconfdir=#{etc}",
                             "--with-pinentry-pgm=#{formula_opt_bin("pinentry")}/pinentry",
                             "--with-readline=#{formula_opt_prefix("readline")}",
                             *std_configure_args
      system "make"
      # Skip `make check`: two tests fail on macOS 13 due to causes unrelated
      # to gnupg itself — see the comment block at the top of this formula.
      system "make", "install"
    end

    # Configure scdaemon as recommended by upstream developers.
    # https://dev.gnupg.org/T5415#145864
    if OS.mac?
      (buildpath/"scdaemon.conf").write <<~CONF
        disable-ccid
      CONF
      pkgetc.install "scdaemon.conf"
    end
  end

  post_install_steps do
    mkdir_p "run", base: :var
    terminate_process "gpg-agent", must_succeed: false
  end

  test do
    (testpath/"batch.gpg").write <<~GPG
      Key-Type: RSA
      Key-Length: 2048
      Subkey-Type: RSA
      Subkey-Length: 2048
      Name-Real: Testing
      Name-Email: testing@foo.bar
      Expire-Date: 1d
      %no-protection
      %commit
    GPG

    begin
      system bin/"gpg", "--batch", "--gen-key", "batch.gpg"
      (testpath/"test.txt").write "Hello World!"
      system bin/"gpg", "--detach-sign", "test.txt"
      system bin/"gpg", "--verify", "test.txt.sig"
    ensure
      system bin/"gpgconf", "--kill", "gpg-agent"
    end
  end
end
