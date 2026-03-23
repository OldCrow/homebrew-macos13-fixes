# homebrew-macos13-fixes

Formulas patched for macOS 13 (Ventura) / Apple Clang 15 compatibility.
These shadow homebrew-core formulas that fail to build or run correctly on
this platform and should be removed as upstream fixes land.

## Formulas

### gnutls
gnutls 3.8.12 fails to build under Apple Clang 15 in C17 mode because
`CRAU_MAYBE_UNUSED` in `lib/crau/crau.h` is never defined — `__has_c_attribute`
is present but returns false for `__maybe_unused__`, leaving the `__GNUC__`
fallback unreachable. The formula carries an inline patch that flattens the
nested `#if` so the `__clang__` path fires correctly.

### itstool / itstool@2.0.7
Built against a local `libxml2` resource with ICU support and Python 3.14
bindings to work around missing system Python XML support on macOS 13.

## Usage

```ruby
tap "oldcrow/macos13-fixes"
brew "oldcrow/macos13-fixes/gnutls"
brew "oldcrow/macos13-fixes/itstool"
```

Or install directly:

```sh
brew install oldcrow/macos13-fixes/gnutls
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).
