# homebrew-macos13-fixes

Homebrew tap of formula overrides for macOS 13 (Ventura) / Apple Clang 15.
These shadow homebrew-core formulas that fail to build or run on this platform.
Per-formula problem/fix notes live in `AGENTS.md` under "Current Fixes".

## How do I install these formulae?

`brew install oldcrow/macos13-fixes/<formula>`

Or `brew tap oldcrow/macos13-fixes` and then `brew install <formula>`.

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "oldcrow/macos13-fixes"
brew "<formula>"
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).
