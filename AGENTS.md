# AGENTS.md

This file provides project-scoped guidance to AI agents and contributors working in this repository.

## Project Overview

`oldcrow/macos13-fixes` is a Homebrew tap of formula overrides targeting macOS 13 (Ventura),
Apple Clang 15 (clang-1500), on an Intel Homebrew prefix (`/usr/local`).

All formulas here shadow homebrew-core formulas that fail to build or run on this platform.
They are temporary: remove each one once homebrew-core ships a Ventura bottle or upstream
fixes the issue. Some overrides fix genuine upstream version-compatibility bugs (not
macOS-specific) that happen to block a build on this platform; note this explicitly in the
formula's header comment when it applies (see Formula Conventions below).

## Session Start

Before patching or reinstalling a formula, confirm the local tap is in sync with remote:

```bash
cd $(brew --repo oldcrow/macos13-fixes)
git fetch && git status
```

If local and remote have diverged, reconcile before making further changes.

## Build Commands

```bash
# Test a patched formula directly (bypasses the confirmation prompts of `brew install`)
brew install --build-from-source oldcrow/macos13-fixes/<formula>

# Audit a formula for style/policy issues before committing
brew audit --strict oldcrow/macos13-fixes/<formula>

# Verify Ruby syntax quickly without invoking a full build
ruby -c Formula/<formula>.rb
```

Dependents that reference an overridden formula by plain name (e.g. `qt` depending on
`qtmultimedia`) do not automatically pick up the tap version. Install the tap-qualified
formula explicitly first so a keg with that name already exists; Homebrew's dependency
resolver then reuses the installed keg instead of rebuilding from homebrew-core.

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
- Set `compatibility_version 1` on patched formulas.
- Use `patch :DATA` + `__END__` for inline patches (preferred over external `.patch` files).
- Skip `make check` only when test failures are demonstrably macOS-specific (SIP sandbox,
  dylib mismatch, etc.). Document the reason in the install block comment.

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
