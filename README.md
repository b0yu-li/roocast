# Roocast

> A native macOS launcher. Fast by default. Light by design.

**Open-source freeware** ([MIT](LICENSE)) — install via Homebrew:

```bash
brew tap b0yu-li/roocast
brew trust b0yu-li/roocast
brew install --cask roocast
```

## What it does

- **Launcher** — ⌘Space app / folder search
- **Clipboard history** — ⌘Esc
- **Calculator**, **zoxide** jumps, light **window snap**, minimal **text expander**, Left-Control **app toggles**

Requires **macOS 14+**. Grant **Accessibility** when prompted.

## Develop

```bash
./dev-install.sh          # release build → /Applications (Apple Development sign)
swift test
```

Distribution / notarization notes: [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md). Design notes for agents: [`AGENTS.md`](AGENTS.md).

## License

MIT © Boyu Li / Rooby Studio
