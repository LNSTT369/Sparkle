# Sparkle Roadmap — Take Nothing

## V1 — Exists Now — SwiftUI Chat
*Status: Shipped at ~/Desktop/Sparkle/V1Chat/SparkleChat.app, streaming on 8081*
- SwiftUI WindowGroup + MenuBarExtra with glass star AppIcon and tray
- Streaming `stream: true` SSE at 79 tok/s text, 76 tok/s vision, TTFT 176ms
- Smallest model `gemma-4-e4b-it-4bit-mlx` 4.8GB, image drop, `/clear` slash, auto scroll pinned to bottom
- Break proof: survives missing server, bad network, restart
- Locked: no more design, appicon frozen at 998K original

## V1.1 — One Click — Zig Single Binary
*Status: Building in background, pid from /tmp/build-mlx.log, MLX 26.0 patched for M2 Max, ~10 min*
- Goal: `brew tap LNSTT369/Sparkle && brew install --cask sparkle` or DMG from https://github.com/LNSTT369/Sparkle/releases, no pip, no python
- Single Zig binary ~7MB at `~/Desktop/Sparkle/zig-out/bin/sparkle`, no Python at runtime
- One port `http://localhost:11234` with OpenAI, Anthropic, Ollama on one wire, like Ollama
- CLI habit: `sparkle run gemma4:e4b` auto pulls if missing then chats, `sparkle list`, `sparkle serve` at 11234 for Claude Code and Open WebUI
- Onboarding for 0 models: First open shows empty state with 3 curated cards, not chat
  - `gemma-4-e4b-it-4bit` 4.8GB — Recommended for 16GB, 74 tok/s, vision
  - `gemma-4-e4b-8bit` 8.9GB — Your 96GB, 81 tok/s
  - `qwen3-coder:30b` 18GB — Coding, like your Ollama `qwen3-coder:30b`
  - Each card: `Download • 4.8GB • 2 min on WiFi` with progress bar, resumable multi-connection like `mlx-serve pull` already does, one click, no HF token needed Apache-2
- Hidden speed: continuous batching, KV 4/8 bit, speculative decoding as defaults, no knobs

## V1.2 — Browser Single Tab
*Status: Roadmap, after V1.1 ships*
- One shared WebKit view, not per agent, not per session
- Tool `browser_use` that the 4.8GB can call, renders inline in chat
- One approval toggle "Allow typing", no vsock VM, no persistent per agent sessions
- Keeps V1 chat as is, adds browser as optional tool

## V1.3 — Spawn Single Delegate
*Status: Roadmap, after V1.2*
- One spawn: delegate to another model on same server, no handoff
- Example: Gemma 4.8GB on 11234 delegates code to `qwen3-coder:30b` 18GB on Ollama `11434` via `http://localhost:11434`, result streamed back
- No RAM safe coexistence, serial queue, no identity chain

## Not Taking
- No 20 plugins, no MCP marketplace, no VM sandbox Linux, no Telegram, no Hey Loki, no folder RAG, no prompt skills until V2
- No 4 tap channels, no LAN Bonjour, no Responses WebSocket launchers
