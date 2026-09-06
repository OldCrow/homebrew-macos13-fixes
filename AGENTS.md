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

# Full test-bot validation. `--tap` is REQUIRED when running locally: test-bot
# defaults to homebrew/core and ignores the working directory, so the bare form
# silently validates core instead of this tap. CI needs no flag because
# setup-homebrew sets the tap context from the checkout.
brew test-bot --only-tap-syntax --tap=oldcrow/macos13-fixes
brew test-bot --only-formulae --tap=oldcrow/macos13-fixes
```

### Native gem builds on Ventura (blocks `brew style` / `audit` / `test-bot`)

Homebrew's portable-ruby 4.0 ships `ruby/internal/stdckdint.h`, which includes the C23
`<stdckdint.h>`. Apple Clang 15 and the macOS 13 SDK do not have that header, so **every**
native gem extension fails at mkmf's first `try_compile` with the misleading
"The compiler failed to generate an executable file ... You have to install development tools
first". Any `brew` command that needs a gem group (`style`, `typecheck`, `test-bot`) triggers
`bundle install`, which then dies on `json`.

Worse, a partially-installed gem breaks `brew` itself: bundler unpacks the Ruby half of
`json` and leaves the native half missing, and the half-gem shadows portable-ruby's working
built-in, so *every* `brew` invocation aborts with
`undefined method 'default_sort_keys_proc=' for class JSON::Ext::Generator::State`.
Recover by moving the incomplete `gems/json-<version>` directory (and the matching
`extensions/<platform>/` entry) out of `Library/Homebrew/vendor/bundle/ruby/<abi>/`.

Fix: build the gems with Homebrew LLVM's clang, which does ship `stdckdint.h`. mkmf ignores
`$CC` — it invokes a bare `clang` from rbconfig — so override it via `PATH`. `brew` sanitises
`PATH` for its subprocesses, so run bundler directly rather than through `brew style`:

```bash
RB=$(brew --repository)/Library/Homebrew/vendor/portable-ruby/<version>/bin
cd $(brew --repository)/Library/Homebrew
PATH=$(brew --prefix llvm)/bin:$RB:$PATH BUNDLE_WITH=style $RB/bundle install
```

This is a one-time cost per `Gemfile.lock` bump: the compiled extensions persist in
`vendor/bundle`, and plain `brew style` works afterwards. All native gems in the bundle
(`json`, `prism`, `racc`, `rbs`) are C-only, so there is no libc++/Apple-Clang ABI mixing
concern; `sorbet-static` and `rubydex` are prebuilt platform gems.

Dependents that reference an overridden formula by plain name do not automatically pick up
the tap version. Install the tap-qualified
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
  changes the formula incompatibly -- including formula-API migrations that leave the installed
  files identical (e.g. `post_install` to `post_install_steps`). Check the current values with
  `grep -rn compatibility_version Formula/` rather than relying on a list here.
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
  `ENV.runtime_cpu_detection` without tripping `FormulaAudit/Miscellaneous`. Currently empty
  (the file is removed); re-create it with the formula name if an override needs that call again.

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

### z3.rb
- **Problem**: (1) P0960R3 parenthesized aggregate init in `obj_hashtable.h` is unsupported by
  Apple Clang 15; (2) `std::format` is unavailable in the macOS 13 SDK libc++.
- **Fix**: add explicit `key_data` constructors, and force-include a `std::format` polyfill that
  avoids the SDK `<format>`.

## Retired Overrides
- **qtmultimedia** (removed at core 6.11.2): the override existed only to add
  `ENV.runtime_cpu_detection` so superenv would stop stripping `-march=`. homebrew-core now
  makes that call itself (citing QTBUG-113391), so the override was pure version lag — and by
  pinning 6.11.1 against a 6.11.2 qtbase it silently broke dependents (see below).
- **qttools** (removed at core 6.11.2): the override kept the vendored litehtml to dodge the
  litehtml 0.10 API break. homebrew-core now backports qlitehtml's upstream litehtml 0.10
  support as a patch (`Patches/qttools/litehtml-0.10.patch`) and builds against system litehtml.
  Same version-lag breakage as qtmultimedia.

**Version-lag hazard (learned 2026-09-06).** Qt submodules require exact-version siblings.
When core moved Qt to 6.11.2 while this tap still pinned qtmultimedia/qttools at 6.11.1,
`qtspeech` and `qttranslations` did not fail loudly: their CMake `find_package` fell back to a
*warning* ("Skipping the build as the condition \"TARGET Qt6::Multimedia\" is not met"),
configure and build succeeded in seconds with nothing to do, and only `cmake --install` failed
with "empty installation". Any Qt-submodule override in this tap must be version-bumped in
lockstep with core's Qt, or retired.

- **libheif** (removed at core 1.23.1): the override existed only to add a missing
  `typedef struct heif_bad_pixel` that broke C consumers (imagemagick's `heic.c`). Upstream
  1.23.1 adds the typedef itself, and core 1.23.1 builds cleanly from source on this platform
  (verified: `imagemagick`/`jasper` rebuild and retain HEIC support). Do not re-add a patch —
  reopen only if a *new*, unrelated Ventura build failure appears.
