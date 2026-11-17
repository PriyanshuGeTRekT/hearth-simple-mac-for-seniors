# Contributing to Hearth

Thanks for helping make Hearth better. Bug reports, ideas and pull requests are all welcome.

- **Found a bug?** Open a [bug report](https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors/issues/new/choose).
- **Have an idea?** Open a [feature request](https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors/issues/new/choose). For bigger changes, please open an issue before you start coding so we can agree on the approach.
- **Found a security problem?** Please don't open an issue. See [SECURITY.md](SECURITY.md).

## Requirements

- A Mac with Apple silicon running **macOS 14 or later**.
- The **Xcode Command Line Tools**. Full Xcode is not needed, and the project is deliberately kept buildable without it.

```bash
xcode-select --install
```

## Building

```bash
git clone https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors.git
cd hearth-simple-mac-for-seniors
./build.sh
```

`build.sh` runs `swift build -c release`, assembles `dist/Hearth.app`, draws the icon, signs it ad hoc and zips it. To try your build:

```bash
ditto dist/Hearth.app /Applications/Hearth.app && open /Applications/Hearth.app
```

## Tests

```bash
./scripts/test.sh
```

`scripts/test.sh` runs `swift test`, adding the Swift Testing plugin path that Command-Line-Tools-only machines need. The app also has a headless self-test that drives its model and renders every screen offscreen:

```bash
dist/Hearth.app/Contents/MacOS/Hearth --selftest
```

and can render all screens to PNG (that is how the screenshots in `docs/` are made):

```bash
dist/Hearth.app/Contents/MacOS/Hearth --render /tmp/hearth-screens
```

All the logic lives in the UI-free core library and is unit-tested; please add tests for anything you change there.

## SwiftUI state

Use `@Local` instead of `@State` in views. In recent SDKs `@State` is a macro whose compiler plugin ships only inside Xcode, so code that uses it does not build with the Command Line Tools alone. `@Local` (in `Sources/Hearth/Local.swift`) behaves the same.

## Style

- Plain words in the interface. The people using these apps are often not technical.
- No network requests, analytics or third-party dependencies.
- Keep it buildable with the Command Line Tools alone.
