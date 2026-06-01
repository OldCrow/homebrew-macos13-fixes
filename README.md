# homebrew-macos13-fixes

Formulas patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
These shadow homebrew-core formulas that fail to build or run correctly on
this platform and should be removed as upstream fixes land.

## Formulas

### gnutls

gnutls 3.8.13 fails to build on Apple Clang 15 (`clang-1500`) because
`CRAU_MAYBE_UNUSED` in `lib/crau/crau.h` expands to `[[__maybe_unused__]]`
when `__has_c_attribute(__maybe_unused__)` is non-zero. Apple Clang 15 then
rejects the no-op stub definitions as conflicting redeclarations of the plain
prototypes, producing 12 "conflicting types" errors. The formula carries an
inline patch that moves the `__clang__` branch before `__has_c_attribute` so
Clang always uses `__attribute__((__unused__))`, which does not alter function
type signatures.

### gnupg

gnupg 2.5.20 `make check` fails on macOS 13 with two test failures:

- `t-http-basic` — SIGABRT under the macOS 13 SIP sandbox. The test opens
  outbound TLS connections that the sandbox blocks.
- `t-ldap-parse-uri` — dyld cannot load `libhogweed.6.dylib`. gnutls was
  compiled against nettle 3.x but nettle 4.0 exports only `libhogweed.7.dylib`.
  Reinstalling `oldcrow/macos13-fixes/gnutls` rebuilds it against the current
  nettle and resolves the dylib mismatch.

The build and install succeed without errors; only the test harness fails.
The formula skips `make check`.

### libheif

libheif 1.22.0 adds `struct heif_bad_pixel` in
`include/libheif/heif_properties.h` but uses the bare identifier
`heif_bad_pixel*` (without the `struct` tag) in the function prototype on
line 338. That is valid C++ but a hard error in C. imagemagick's
`coders/heic.c` is a plain C translation unit, so Apple Clang 15 rejects
the include with:

```
heif_properties.h:338:56: error: must use 'struct' tag to refer to type 'heif_bad_pixel'
```

The formula carries an inline patch that adds
`typedef struct heif_bad_pixel heif_bad_pixel;` immediately after the struct
definition, making the bare identifier valid in both C and C++.

### itstool / itstool@2.0.7

Built against a local `libxml2` resource with ICU support and Python 3.14
bindings to work around missing system Python XML support on macOS 13.

## Usage

```ruby
tap "oldcrow/macos13-fixes"
brew "oldcrow/macos13-fixes/gnutls"
brew "oldcrow/macos13-fixes/gnupg"
brew "oldcrow/macos13-fixes/libheif"
brew "oldcrow/macos13-fixes/itstool"
```

Or install directly:

```sh
brew install oldcrow/macos13-fixes/gnutls
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).
