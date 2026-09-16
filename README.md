<p align="center">
  <img src="docs/hero.png" width="720" alt="Sparkle V1 hero">
</p>

<h1 align="center">Sparkle</h1>

<p align="center">
  <strong>Own your AI. No cloud. No token.</strong><br>
  Chat, image, and vision on your Mac. Offline. One download.
</p>

<p align="center">
  <a href="https://github.com/LNSTT369/Sparkle/releases/latest/download/Sparkle.dmg">
    <img src="https://img.shields.io/badge/Download-Sparkle.dmg-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
  <br>
  <sub>Apple Silicon · macOS 14+ · 5GB with gemma-4-e4b-it-4bit inside · No HF token</sub>
</p>

---

### One download

Drag `Sparkle.dmg` to `/Applications`, open, and chat. The 4.8GB `gemma-4-e4b-it-4bit` is already inside `Contents/Resources/models`, no cards, no `Download` wait.

### What it does

* Chat at 79 tok/s, vision at 76 tok/s, image drop inline
* Streaming typewriter, `/clear` to reset, `⌘,` for the other two models hidden in Settings
* Menu bar star, dock star, `stream: true` on `http://127.0.0.1:11234` for Claude Code

### For the curious

```bash
brew tap LNSTT369/Sparkle && brew install --cask sparkle
sparkle run gemma4:e4b  # same 4.8GB, auto pulls if you use the Lite build
```

MIT. Built in Swift + Zig, no Electron, no Python at runtime.

<p align="center">
  <img src="docs/hero.png" width="360" alt="Chat with image">
  <br>
  <sub>Drop a photo, ask, get an answer. No cloud.</sub>
</p>
