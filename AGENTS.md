# AGENTS.md

This file provides project-scoped guidance to AI agents and contributors working in this repository.

## Project Overview

`oldcrow/macos13-fixes` is a Homebrew tap of formula overrides targeting macOS 13 (Ventura),
Apple Clang 15 (clang-1500), on an Intel Homebrew prefix (`/usr/local`).

All formulas here shadow homebrew-core formulas that fail to build or run on this platform.
They are temporary: remove each one once upstream fixes the issue. macOS 13 is now Tier 3 and
homebrew-core no longer builds Ventura bottles for these formulas (the oldest Intel bottle is
`sonoma`), so the realistic retirement trigger is an upstream source fix, not a bottle — do not
wait for one. Some overrides fix genuine upstream version-compatibility bugs (not macOS-specific)
that happen to block a build on this platform; note this explicitly in the formula's header
comment when it applies (see Formula Conventions below).

## Session Start

Before patching or reinstalling a formula, confirm the local tap is in sync with remote:

```bash
cd $(brew --repo oldcrow/macos13-fixes)
git fetch && git status
```

If local and remote have diverged, reconcile before making further changes.

## Build Commands

```bash
# Verify Ruby syntax quickly without invoking a full build
ruby -c Formula/<formula>.rb

# Lint style (autofix with --fix) and audit policy before committing
brew style oldcrow/macos13-fixes
brew audit --strict oldcrow/macos13-fixes/<formula>

# Test a patched formula directly (bypasses the confirmation prompts of `brew install`)
brew install --build-from-source oldcrow/macos13-fixes/<formula>

# Run formula tests
brew test oldcrow/macos13-fixes/<formula>

# Full test-bot validation (as CI runs)
brew test-bot --only-tap-syntax
brew test-bot --only-formulae
```

Dependents that reference an overridden formula by plain name (e.g. `qt` depending on
`qtmultimedia`) do not automatically pick up the tap version. Install the tap-qualified
formula explicitly first so a keg with that name already exists; Homebrew's dependency
resolver then reuses the installed keg instead of rebuilding from homebrew-core.

### Creating/Updating Formulae

Formulae are based on upstream homebrew-core but modified for macOS 13 compatibility. When
bumping a formula:

1. Compare against current upstream:
   `/usr/local/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/`
2. Preserve the macOS 13-specific modifications (patches, skipped tests, env tweaks).
3. Update `url`, `sha256`, and fold in any new upstream changes; re-verify inline patches still
   apply against the new source before committing.

## Upstream Issue Reporting

Most formulas in this tap exist purely because of macOS 13 / Apple Clang 15 incompatibilities.
Some do not: the root cause is a genuine upstream bug or version-compatibility break that would
fail on any OS building from source (e.g. a dependency bump that breaks a consumer's API
assumptions, not a macOS-specific compiler quirk). When diagnosing a build failure turns out to
be one of these broader cases, tell the User before committing the formula and ask whether they
want to draft an issue for the relevant project's upstream tracker or Homebrew's discussion
forums. Do not draft or file the issue unprompted.

## Formula Conventions
- Begin each file with a comment block: problem description, root cause, fix applied,
  and a "Remove this formula once..." line.
- Set `compatibility_version` on patched formulas: start at `1`, and bump it whenever a revision
  changes the formula incompatibly (`gcc` and `z3` are at `2`).
- Use `patch :DATA` + `__END__` for inline patches (preferred over external `.patch` files).
- Skip `make check` only when test failures are demonstrably macOS-specific (SIP sandbox,
  dylib mismatch, etc.). Document the reason in the install block comment.
- Homebrew's rubocop config forbids inline `# rubocop:disable` directives
  (`Style/DisableCopsWithinSourceCodeDirective`). When a deliberate choice trips a cop that has a
  tap-level allowlist (e.g. `FormulaAudit/Miscellaneous`'s `ENV.runtime_cpu_detection` check),
  add the formula name to the matching `style_exceptions/*.json` file at the tap root instead —
  the same mechanism homebrew-core itself uses (see `style_exceptions/` below). Cops without an
  allowlist must be satisfied by changing the code, not suppressed.
- **IMPORTANT**: `brew style` result caching. RuboCop caches inspection results at
  `$(brew --cache)/style/<uid>/rubocop_cache`, keyed by file content and cop config — but *not*
  by `style_exceptions/*.json` content. After adding or editing a `style_exceptions/*.json` file,
  clear that cache directory before re-running `brew style`, or the stale (pre-exception) result
  will still be reported.

### style_exceptions/
- `runtime_cpu_detection_allowlist.json` — lists formulae allowed to call
  `ENV.runtime_cpu_detection` without tripping `FormulaAudit/Miscellaneous`. Currently:
  `qtmultimedia` (required to stop superenv stripping `-march=`; see the formula header — Qt's
  AVX2 dispatch is runtime-guarded, so the call is safe here).

## Known Apple Clang 15 Failure Patterns
- **C23 attribute syntax conflict**: `[[__maybe_unused__]]` expands via `__has_c_attribute`
  and Apple Clang 15 rejects it as a conflicting redeclaration of a plain prototype.
  Fix: guard with `defined(__clang__)` first to force `__attribute__((__unused__))`.
- **Missing struct typedef**: bare `Foo*` is valid C++ but a hard error in C translation units.
  Fix: add `typedef struct Foo Foo;` after the struct definition.
- **SIP sandbox blocking network**: test targets that open outbound TLS connections SIGABRT
  inside the Homebrew build sandbox on macOS 13. Fix: skip `make check`.
- **dylib soversion mismatch**: a dependency soname bump (e.g. nettle 3→4,
  `libhogweed.6→.7`) leaves a dependent linked against the old soversion.
  Fix: rebuild the dependent against the updated dep via a companion formula in this tap.
- **superenv strips `-march=` flags**: Homebrew's build shim drops all `-march=` flags
  unless the formula calls `ENV.runtime_cpu_detection`. Formulas with per-file SIMD
  dispatch (e.g. Qt's AVX2 conversion helpers) silently lose their target-feature flags
  and fail with "requires target feature 'avx', but would be inlined into a function
  compiled without support for 'avx'". Fix: call `ENV.runtime_cpu_detection` in `install`.
- **P0960R3 parenthesized aggregate initialization**: `T(args)` aggregate construction was not
  implemented in Clang until 16, so Apple Clang 15 rejects e.g. `key_data(k, v)` when the type
  has only implicit constructors. Fix: use brace-init `T{args}` or add explicit constructors.
  (10.15 / Apple Clang 12 fails here too, but that tap builds with Homebrew LLVM; on Ventura a
  small source patch suffices.)
- **`std::format` unavailable in the macOS 13 SDK libc++**: the header is gated twice —
  `_LIBCPP_HAS_NO_INCOMPLETE_FORMAT` hides the `<format>` implementation, and
  `_LIBCPP_AVAILABILITY_FORMAT` marks the types `unavailable` for macOS < 14, so even unlocking
  the first guard fails template substitution. Fix: force-include (`-include`) a self-contained
  polyfill that never touches the SDK `<format>`. This differs from 10.15, where libc++ lacks
  `std::format` entirely and the fix is the Homebrew LLVM toolchain.

## Known Homebrew 6.x Tooling Pitfalls
- **Tap-relative `file:` patches fail via the JSON API**: Homebrew 6.x loads formulas from the
  JSON API by default, where the formula object has no `tap.path`, so a `patch do ... file "..."`
  reference raises `ArgumentError: Patch file must be within the formula repository`. Fix: pin the
  patch to a raw URL (with `sha256`) instead of a `file` reference (see `gcc.rb`).

## Current Fixes

### gcc.rb
- **Problem**: the macOS patch is referenced via a tap-relative `file:` path that Homebrew 6.x
  cannot resolve when loading from the JSON API. Not a compiler issue.
- **Fix**: replace the `file` reference with a pinned raw-URL patch (same diff, verified by
  `sha256`).

### gnupg.rb
- **Problem**: `make check` fails on macOS 13 — `t-http-basic` SIGABRTs under the SIP sandbox
  (blocked outbound TLS) and `t-ldap-parse-uri` cannot load `libhogweed.6.dylib` after the
  nettle 3→4 soname bump.
- **Fix**: skip `make check`; build/install are unaffected. Rebuild the companion `gnutls`
  against current nettle to clear the dylib mismatch.

### gnutls.rb
- **Problem**: `CRAU_MAYBE_UNUSED` expands to the C23 `[[__maybe_unused__]]` on Apple Clang 15,
  which rejects the stub definitions as conflicting redeclarations (12 errors).
- **Fix**: inline patch moves the `__clang__` branch ahead of `__has_c_attribute` so the
  `__attribute__((__unused__))` form is always used.

### itstool.rb / itstool@2.0.7.rb
- **Problem**: macOS 13 lacks system Python XML support; itstool needs libxml2 Python bindings
  with ICU.
- **Fix**: build against a bundled `libxml2` resource with ICU support and Python 3.14 bindings.
- **Key dependency**: `icu4c@78`, `libxml2`, `python@3.14`.

### libheif.rb (retirement candidate)
- **Problem**: 1.22.0 declared `struct heif_bad_pixel` but referenced it without the `struct`
  tag — a hard error when a C consumer (imagemagick's `heic.c`) includes the header.
- **Fix**: inline patch adds the missing `typedef`.
- **Status**: upstream 1.23.1 adds the typedef itself, so this override is obsolete. Retire it
  once core 1.23.1 is confirmed to build on Ventura (rebuilds `imagemagick`/`qt`).

### qtmultimedia.rb
- **Problem**: superenv strips `-march=`, so Qt's per-file AVX2 SIMD dispatch fails to compile
  its always-inline AVX2 intrinsics on Apple Clang 15.
- **Fix**: call `ENV.runtime_cpu_detection` so superenv preserves `-march=`; allowlisted in
  `style_exceptions/runtime_cpu_detection_allowlist.json` (see Formula Conventions above).

### qttools.rb
- **Problem**: not a macOS/Clang issue — homebrew-core's litehtml 0.10 changed the
  `background_paint` API and coordinate types; qttools' bundled `qlitehtml` wrapper was not
  updated, so building against the external system litehtml fails.
- **Fix**: keep the vendored `qlitehtml` litehtml copy instead of forcing the newer external one.

### z3.rb
- **Problem**: (1) P0960R3 parenthesized aggregate init in `obj_hashtable.h` is unsupported by
  Apple Clang 15; (2) `std::format` is unavailable in the macOS 13 SDK libc++.
- **Fix**: add explicit `key_data` constructors, and force-include a `std::format` polyfill that
  avoids the SDK `<format>`.
