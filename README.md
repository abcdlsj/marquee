# Marquee

An iOS movie collection backed by Emby. Browse favorites as a gallery, mark what you've watched, see the year as a heatmap, and export share posters.

Requires iOS 26 and Xcode 26 with `xcodegen`.

## Install on iPhone

```bash
scripts/install-ios.sh              # paired iPhone, seeded with Ember's active server
scripts/install-ios.sh --simulator  # booted simulator
scripts/install-ios.sh --no-seed    # add servers manually in the app
```

The seed is read from `~/.ember/servers.json` at build time and baked into the debug build's Info.plist; the app moves it into the Keychain on first launch.
