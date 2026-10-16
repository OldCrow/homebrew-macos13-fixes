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
brew test-bot --only-formulae --tap=oldcrow/macos13-fixes  # local only; CI no longer runs this
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

## CI/CD

- `tests.yml`: runs `brew test-bot --only-tap-syntax` on a single `ubuntu-24.04` runner.
- `publish.yml`: merges PRs and publishes bottles when the `pr-pull` label is applied. Dormant --
  nothing produces bottles now that `--only-formulae` is gone; keep it only if that changes.
- `ubuntu-24.04` is pinned, not `ubuntu-22.04`: 22.04's glibc 2.35 is older than current Homebrew
  expects and `brew doctor` (run by `--only-setup`) treats the mismatch as a hard failure. 22.04
  also begins deprecation on 2026-09-17.

### Why one Linux runner and no macOS matrix (audited 2026-09-06)

CI cannot build what this tap fixes: GitHub removed the macOS 13 runners on 2025-12-08, so no
hosted runner runs Ventura or Apple Clang 15. Everything CI *can* check -- `brew style`,
`brew readall --os=all --arch=all`, `brew audit` -- is platform-independent Ruby linting that
returns the same result on every runner, so a macOS matrix re-derived an identical answer at 10x
the per-minute cost.

It also imported unrelated breakage. On 2026-09-02 homebrew-core dropped gmp's Intel macOS
bottles (`arm64_*` and Linux only). `brew style` installs `shellcheck`, which needs `gmp`, so on
`macos-15-intel` it began source-building gmp and hung ~29 minutes on unreachable `gmplib.org`
and `ftpmirror.gnu.org` before failing. Every push from 2026-09-02 onward failed on that leg
alone, while the ubuntu and macos-26 legs passed in about a minute.

`--only-formulae` and the bottle-artifact upload were dropped with the matrix: both were gated on
`pull_request`, this repo pushes straight to main, and a build on Sequoia/Tahoe would exercise the
wrong compiler regardless.

Real build validation is local, on a Ventura machine -- see Build Commands above.

## Upstream Issue Reporting

Most formulas in this tap exist purely because of macOS 13 / Apple Clang 15 incompatibilities.
Some do not: the root cause is a genuine upstream bug or version-compatibility break that would
fail on any OS building from source (e.g. a dependency bump that breaks a consumer's API
assumptions, not a macOS-specific compiler quirk). When diagnosing a build failure turns out to
be one of these broader cases, tell the User before committing the formula and ask whether they
want to draft an issue for the relevant project's upstream tracker. Do not draft or file the
issue unprompted.

Do not offer Homebrew issues or discussions for these cases: Homebrew is likely to decline
fixes for configurations it is about to drop. Upstream project issues (e.g. simdutf/simdutf#1045)
remain worth offering, since the fix reaches all users.

Homebrew's timeline (https://docs.brew.sh/Support-Tiers, checked 2026-09-25):
- Since September 2026, Intel x86_64 macOS is Tier 3 for Big Sur 11 through Tahoe 26, and
  Catalina 10.15 and earlier are unsupported. Tahoe 26 is the last macOS for Intel, and Homebrew
  no longer builds Intel bottles.
- In or after September 2027, all Intel macOS becomes unsupported, and Homebrew "will remove the
  ability to run Homebrew on Intel systems". Apple Silicon moves to Tier 3 for Monterey 12
  through Sequoia 15.

This tap's Intel Ventura prefix (`/usr/local`) therefore has an expected end of September 2027,
earlier than any Ventura cutoff on Apple Silicon (extrapolated to 2028 at the earliest). For Intel
macOS Sequoia 15 and earlier, `brew doctor` suggests MacPorts as the fallback.

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
  `ENV.runtime_cpu_detection` without tripping `FormulaAudit/Miscellaneous`. Currently:
  `qtbase` (homebrew-core's own formula makes the call, citing QTBUG-113391; the override keeps
  it unchanged). Remove the file when no override needs the call.

## Known Apple Clang 15 Failure Patterns
- **C23 attribute syntax conflict**: `[[__maybe_unused__]]` expands via `__has_c_attribute`
  and Apple Clang 15 rejects it as a conflicting redeclaration of a plain prototype.
  Fix: guard with `defined(__clang__)` first to force `__attribute__((__unused__))`.
- **Missing struct typedef**: bare `Foo*` is valid C++ but a hard error in C translation units.
  Fix: add `typedef struct Foo Foo;` after the struct definition.
- **Lambda capture of a structured binding**: C++20 (P1091R3) allows it, Clang implements it
  only from 16. Fix: copy the binding into a named local before the lambda.
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
- **Toolchain parity with an LLVM-built consumer**: formulas with `fails_with :clang { build 1699 }`
  (e.g. `node`) build with Homebrew LLVM and its libc++ headers. If a dependency probes libc++
  features to decide what it compiles (simdutf's `SIMDUTF_ATOMIC_REF` needs `std::atomic_ref`,
  absent from the macOS 13 SDK libc++), an Apple-Clang-built dependency omits symbols the consumer
  expects, and the consumer fails at link time with undefined symbols. Fix: give the dependency
  the same `fails_with :clang` + `depends_on "llvm" => :build` rule. Before doing so, confirm no
  ABI risk for Apple Clang callers: libc++ ABI v1 on both sides, identical layout of every `std::`
  type crossing the API, no feature-probed guards inside exported classes, and every libc++
  import present in the system `/usr/lib/libc++.1.dylib` (see simdutf.rb below).
- **`std::format` unavailable in the macOS 13 SDK libc++**: the header is gated twice —
  `_LIBCPP_HAS_NO_INCOMPLETE_FORMAT` hides the `<format>` implementation, and
  `_LIBCPP_AVAILABILITY_FORMAT` marks the types `unavailable` for macOS < 14, so even unlocking
  the first guard fails template substitution. Fix: force-include (`-include`) a self-contained
  polyfill that never touches the SDK `<format>`. This differs from 10.15, where libc++ lacks
  `std::format` entirely and the fix is the Homebrew LLVM toolchain.
- **Upstream raised its minimum macOS above 13**: a project that now requires a 14.x+ deployment
  target (Qt 6.12: macOS 14.4 / SDK 15) includes headers the macOS 13 SDK does not have
  (`os/os_sync_wait_on_address.h`, 14.4+). homebrew-core may suppress the project's own SDK check
  (`-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON`), so configure passes and the first hard dependency
  fails to compile. Fix: shim the new API over the older syscall it wraps when
  `__MAC_OS_X_VERSION_MIN_REQUIRED` is below the API's introduction (see qtbase.rb). Expect no
  upstream fix — the platform was dropped on purpose. Also check the project's *default deployment
  target*: Qt 6.12 sets `CMAKE_OSX_DEPLOYMENT_TARGET` to its 14.4 minimum when none is given, so
  a header-level fix alone still yields `-mmacosx-version-min=14.4` objects that dyld refuses to
  load on 13; pin the target to `MacOS.version` and make sure it propagates to dependents.
- **Which SDK Homebrew picks**: with both CLT and Xcode installed, superenv uses the CLT SDK
  matching the host version (13.3 here) unless the formula has `depends_on xcode: :build`, which
  switches to Xcode's SDK (14.2 with Xcode 15.2). A formula that drops its `xcode` dependency on a
  version bump silently changes SDK and surfaces every "macOS 14 API used unconditionally" error
  that the previous version never showed. Compare `HOMEBREW_SDKROOT` in the old and new
  `~/Library/Logs/Homebrew/<formula>/*.log` before patching sources (see qtbase.rb).
- **libc++ 23 header hygiene**: Homebrew LLVM 23's libc++ stopped transitively including
  `<vector>`, `<optional>`, `<concepts>`, `<cstdint>` etc. from other headers. Sources that relied
  on that fail with "no member named 'vector' in namespace 'std'" only on the `fails_with :clang`
  → Homebrew LLVM path, which is every C++20 formula on Ventura. Fix: backport the upstream
  include additions (see ada-url.rb).
- **Tap override version lag breaks dependents in Ruby**: `Formula["name"]` in a dependent's
  `install` resolves to the *core* formula, so `.prefix` / `.prefix.realpath` points at a Cellar
  version that is not installed when this tap pins an older one (`Errno::ENOENT`, no build log
  for the failing step). Fix: bump the override, never pin behind core (see gcc.rb).

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
  `sha256`). Otherwise identical to homebrew-core.
- **Lockstep**: must track core's gcc version. Dependents resolve `Formula["gcc"]` to the *core*
  formula; `r` calls `Formula["gcc"].prefix.realpath` after its build and raised
  `Errno::ENOENT ... /usr/local/Cellar/gcc/16.2.0` while the tap keg was still 16.1.0
  (2026-10-15). A version lag here breaks dependents at install time, not at build time.

### ada-url.rb
- **Problem**: ada 4.0.0's headers use `std::vector`, `std::optional` and `std::same_as` without
  including `<vector>`, `<optional>`, `<concepts>`. core builds ada-url with Homebrew LLVM when
  `clang_build_version <= 1500` (`fails_with :clang`), and LLVM 23's libc++ no longer includes
  those transitively, so compilation fails in `url_pattern_regex.h`. Not Ventura-specific: any
  libc++ 23 source build of 4.0.0 fails. Blocks `node` (ada-url is a dependency).
- **Fix**: inline backport of ada-url/ada@d85b80412f11 (#1292, "Add missing includes of standard
  library headers"): the commit's hunks for files that exist in 4.0.0, plus hand-ported includes
  for the four files whose context moved. Retire when core moves past 4.0.0.

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

### simdutf.rb
- **Problem**: node 26.10.0 builds V8 against the shared simdutf and calls its atomic base64 API.
  node builds with Homebrew LLVM (`fails_with :clang` build 1699), whose libc++ has
  `std::atomic_ref`; core simdutf builds with Apple Clang 15 and the SDK libc++, which lacks it, so
  `SIMDUTF_ATOMIC_REF` is unset, the atomic API is compiled out, and node's `mksnapshot` link fails
  with undefined `simdutf::atomic_*`. Under Apple Clang the base64 benchmark also fails to compile
  (it guards the calls by C++ version instead of `SIMDUTF_ATOMIC_REF`; simdutf/simdutf#1045).
- **Fix**: same toolchain rule as node (`fails_with :clang` build 1699, `llvm` build dep). No
  source patch: with LLVM's libc++ the benchmark compiles unpatched.

### qtbase.rb
- **Problem**: Qt 6.12.0 requires macOS 14.4 (SDK 15, Xcode 16). homebrew-core passes
  `-DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON`, so configure succeeds on Ventura and compilation fails
  in `src/corelib/thread/qfutex_mac_p.h`: `os/os_sync_wait_on_address.h` (macOS 14.4 SDK) is
  missing. 6.12 made the Darwin futex unconditional (`QT_ALWAYS_USE_FUTEX`,
  `FutexAlwaysAvailable = true` in the public `qmutex.h`) and removed the Mach-semaphore mutex
  fallback (`qmutex_mac.cpp`); the generic Unix fallback uses `sem_init()`, which macOS does not
  implement, so reverting to 6.11's runtime-detected futex is not viable.
- **Fix** (four parts, all in one `patch :DATA` plus two formula lines):
  1. `qfutex_mac_p.h`: when the SDK lacks the header or `__MAC_OS_X_VERSION_MIN_REQUIRED <
     140400`, define the four `os_sync_*` functions as inline shims over
     `__ulock_wait2`/`__ulock_wake` (macOS 11+; the syscalls Qt 6.11 called directly and that
     libplatform's `os_sync_*` wrap). Verified against the macOS 13 SDK: both syscalls are
     exported by `libsystem_kernel`, timeouts report `ETIMEDOUT`, 32- and 64-bit waits and wakes
     work. The SDK header is used unchanged on 14.4+ targets.
  2. Deployment target: 6.12.0 also dropped core's `-DCMAKE_OSX_DEPLOYMENT_TARGET=min(host,
     sonoma)` (present 6.9.3-6.11.2), so Qt defaulted it to its 14.4 minimum: every object was
     built `-mmacosx-version-min=14.4` (the shim never engaged) and the result would not load on
     13. The formula pins `-DCMAKE_OSX_DEPLOYMENT_TARGET=#{MacOS.version}`; the patch teaches the
     installed `QtAutoDetectHelpers.cmake` (used by every qt* submodule via Qt6 BuildInternals)
     to honour `$MACOSX_DEPLOYMENT_TARGET` or the host version when older than Qt's minimum.
  3. SDK: 6.12.0 dropped `depends_on xcode: :build` too, so Homebrew picked the CLT's 13.3 SDK
     instead of Xcode 15.2's 14.2 SDK, and the Cocoa/Darwin code uses 14.0-14.2 API
     unconditionally (`NSView.clipsToBounds`, `EKAuthorizationStatusFullAccess`, CALayer HDR
     flag). The formula restores `depends_on xcode: :build`. Guards for the EventKit and HDR
     cases are kept in the patch so a 13-SDK build also works.
  4. `qcocoascreen.mm`: the screenshot path moved to `SCScreenshotManager` and
     `getCurrentProcessShareableContentWithCompletionHandler:` (14.4 SDK); restored the 6.11
     `CGDisplayCreateImageForRect` grab behind `QT_APPLE_SDK_EQUAL_OR_ABOVE(MACOS(14, 4))`.
- **Lockstep**: this is a Qt submodule override, so it must track homebrew-core's qtbase version
  exactly (see "Version-lag hazard" under Retired Overrides). Every other `qt*` formula still
  comes from homebrew-core. Install `oldcrow/macos13-fixes/qtbase` before `brew upgrade` or
  `brew bundle` touches the rest of Qt, so dependents reuse the keg.
- **Upstream**: none expected; Qt dropped macOS 13 deliberately. Retire with the machine.

### qtdeclarative.rb (and any further Qt submodule override of the same shape)
- **Problem**: core builds the submodules against the CLT 13.3 SDK and Qt 6.12 uses macOS 14 SDK
  API unconditionally (`qtdeclarative`: `NSColor.secondarySystemFillColor` /
  `tertiarySystemFillColor` in `qquickstyleconstants.mm`).
- **Fix**: core formula plus `depends_on xcode: :build` inside `on_macos`, so superenv uses Xcode
  15.2's 14.2 SDK. No source patch. The deployment target stays 13 via the patched
  `QtAutoDetectHelpers.cmake` that the tap qtbase installs. Generate further ones the same way
  (header comment naming the module and symptom, `on_macos` block, bottle block dropped), add a
  gated Brewfile entry between `qtbase` and `qt`, and keep every one in lockstep with core's Qt.
- **Install order**: core `brew upgrade qt` stops at the first failing module. Uninstall the core
  keg (`brew uninstall --ignore-dependencies <module>`), install the tap one, then rerun
  `brew upgrade qt`.
- **ABI check (2026-09-25)**: no risk to Apple Clang callers. Both libc++ header sets are ABI v1
  with the standard string layout; `std::string_view`, `std::tuple<result, size_t>`,
  `simdutf::result`/`full_result` and `internal::atomic_ptr` have identical size, alignment and
  offsets under AppleClang C++17/C++20 and LLVM 23; the virtual `implementation` class is guarded
  only by `SIMDUTF_FEATURE_*` build options (`std::vector` appears only under
  `SIMDUTF_INTERNAL_TESTS`); the dylib still links `/usr/lib/libc++.1.dylib` and imports only
  `__cxa_*` runtime symbols from it; no abi-tagged exports. An AppleClang-built caller ran
  correctly against the LLVM-built dylib.
- **Retire when**: homebrew-core simdutf builds with node's toolchain, or ships a bottle for this
  platform. Not Ventura-specific: any macOS with clang build <= 1699 and no simdutf bottle
  (Intel, Sonoma) hits the same mismatch.

### qtmultimedia.rb
- **Problem**: `qdarwinformatsinfo.mm` (darwin plugin) captures the structured binding
  `containerName` in two lambdas. C++20 P1091R3 allows that, but Clang implements it only from
  version 16; Apple Clang 15 fails with `reference to local binding 'containerName' declared in
  enclosing function`. Not an SDK issue: core already has `depends_on xcode` and
  `ENV.runtime_cpu_detection` (so `qtmultimedia` is in `runtime_cpu_detection_allowlist.json`).
- **Fix**: core formula minus bottle block, `patch :DATA` copying the binding to a plain local
  (`const char *const container`) used by both lambdas. Same lockstep and install-order rules as
  qtdeclarative above.
- **Retire when**: this machine leaves Apple Clang 15, or upstream stops capturing the binding.

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
