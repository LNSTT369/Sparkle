# Sparkle — Take Nothing MLX Chat for Apple Silicon

Stripped fork of `ddalcu/mlx-serve`. One binary, one port, chat + image only. No Python, no bloat.

**V1 is opinionated:** Apple Silicon only, macOS 26.2+, 3 curated models. Everything else is cut.

## What we kept from mlx-serve

* **No Python at runtime, single Zig binary** — `build.zig` fetches Zig + mlx + llama.cpp, ~7MB. Strip frameworks.
* **Homebrew Cask + DMG notarized** — `brew tap LNSTT369/Sparkle && brew install --cask sparkle` + GitHub Releases. One channel.
* **One port, 3 APIs** — `http://localhost:11234` speaks OpenAI, Anthropic, Ollama `/api/chat`. Works with Claude Code, OpenCode, Pi, Open WebUI with no config. One wire.
* **Resumable HF downloads** — finds existing LM Studio models, multi-connection. Break proof.
* **Hidden speed** — continuous batching, KV-cache 4/8-bit, speculative decoding as defaults. No knobs.

## What we cut for Take Nothing

* No `containers/` — removed sandboxed Linux VM agent shell (`agent-shell-mlxserve`, `guest-kernel`)
* No `website/` — docs site, keep `docs/` minimal
* No 4 tap channels, no `containers` folder. One Cask only.
* No LAN Bonjour sharing — local only.
* No Responses WebSocket + openclaw/hermes launchers — one flag `--port 8080` is enough.
* No exposed tuning knobs — only `temp` and `max_tokens`.
* No full MLX Core scope — no MCP marketplace, no VM sandbox, no Telegram bridge, no Hey Loki hands-free, no folder RAG, no prompt skills. V1 is chat + image drop only.

## Get started

Needs macOS 26.2+ on Apple Silicon, Xcode + Metal Toolchain.

```bash
git clone https://github.com/LNSTT369/Sparkle && cd Sparkle
brew bundle install --file=Brewfile
./app/build.sh
# or CLI only
zig build
```

```bash
# chat, auto download + REPL, 3 curated models only
./zig-out/bin/sparkle run gemma4:e4b --port 8080
./zig-out/bin/sparkle run qwen3-coder:30b
./zig-out/bin/sparkle pull gemma4
./zig-out/bin/sparkle list
./zig-out/bin/sparkle serve
```

Point any OpenAI or Anthropic client at `http://localhost:8080` with your `~/models/gemma-4-e4b-8bit-mlx`.

## V1 Models — curated, not 3000

* `gemma-4-e4b-8bit-mlx` 8.9GB — your current MLX, chat + vision, default
* `gemma-4-e4b-it-4bit` 5GB — for 16GB Macs
* `qwen3-coder:30b` 18GB — coding, same as Ollama `qwen3-coder:30b`

Forked from https://github.com/ddalcu/mlx-serve — MIT. See `NOTICE` and original `CHANGELOG.md`.

