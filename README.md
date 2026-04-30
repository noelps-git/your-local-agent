<div align="center">

<pre>
█ █ ▄█▄ █ █ ██
▀█▀ █ █ █ █ ██
 █  █ █ █ █ █▄█
 █  ▀█▀ ▀█▀ █ █

█   ▄█▄  ██ ▄█▄ █    ▄█▄  ██ ███ █ █ ███
█   █ █ █   ███ █    ███ █   ██  ███  █
█   █ █ █   █ █ █    █ █ █ █ █   █ █  █
███ ▀█▀  ██ █ █ ███  █ █  ██ ███ █ █  █
</pre>

### The AI that runs on your machine — not theirs.

*No cloud. No API keys. No bill. No one watching.*

[![macOS](https://img.shields.io/badge/macOS-12%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%20→%20M4-black?style=flat-square)](https://www.apple.com/mac/)
[![Models](https://img.shields.io/badge/model-Qwen3%204B–32B-black?style=flat-square)](https://huggingface.co/ggml-org)
[![License](https://img.shields.io/badge/license-MIT-black?style=flat-square)](LICENSE)
[![Free](https://img.shields.io/badge/cost-free%20forever-black?style=flat-square)]()

</div>

---

## Why local?

Every AI assistant you've used lives somewhere else. Your prompts travel over the internet, get logged, filtered, and processed on hardware you'll never see. That's fine for most things.

But when you're debugging at 2am. Writing scripts you'd rather not explain. Asking the same question for the fifteenth time. Working offline. Asking about anything that would get you flagged on a cloud provider —

You want it **on your machine**.

**your-local-agent** puts a full AI assistant — model, inference engine, coding agent — entirely on your Mac. One command to install. One command to start. **Nothing leaves your machine. Ever.**

---

## Before you start

Make sure your machine meets these requirements before running anything.

### Hard requirements

| Requirement | Minimum | Notes |
|---|---|---|
| **macOS** | 12 Monterey | Works on 13, 14, 15 too |
| **Chip** | Apple Silicon (M1+) | M2/M3/M4 recommended |
| **RAM** | 8 GB | 16 GB+ for better models |
| **Free disk** | 8 GB | Up to 20 GB for the 32B model |
| **Internet** | Required once | Only for initial setup and updates |

### Software prerequisites

The setup script installs most things automatically, but these must exist first:

**1. Xcode Command Line Tools** — needed to build llama.cpp

```bash
xcode-select --install
```

> If you see *"command line tools are already installed"*, you're good.

**2. Python 3** — used to parse models and state files

```bash
python3 --version
```

> macOS ships with Python 3 since Monterey. If missing: `brew install python3`

**3. curl** — needed to fetch the setup script

```bash
curl --version
```

> Comes pre-installed on macOS. If somehow missing: `brew install curl`

**4. A supported shell** — zsh or bash

```bash
echo $SHELL
```

> Zsh is the default on macOS Catalina and later. Both are fully supported.

---

## Install

### One-liner (recommended)

Paste this in your terminal and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/noelps-git/your-local-agent/main/setup.sh | bash
```

That's it. The script:
1. Detects your RAM, chip, and disk space
2. Installs Homebrew, llama.cpp, Node.js, and Aider (skips anything already installed)
3. Downloads the right AI model for your exact hardware
4. Configures everything and wires up your shell aliases
5. Runs a live test to confirm the agent is working

> **Estimated time:** 10–30 minutes depending on your internet speed and which model is selected.

### From source (if you cloned the repo)

```bash
git clone https://github.com/noelps-git/your-local-agent.git
cd your-local-agent
bash setup.sh
```

---

## First launch

After setup finishes, **restart your terminal**, then:

```bash
local-ai-start
```

Your local AI is now running. Open a project folder and start talking to it.

---

## Daily commands

```bash
local-ai-start     # start the server and launch Aider
local-ai-stop      # shut everything down
local-ai-status    # check if the server is running
local-ai-info      # show which model is loaded and on which port
local-ai-update    # pull latest scripts + check for better models
```

---

## Which model do you get?

Setup reads your RAM and picks automatically. No config files, no manual decisions.

| RAM | Model | Size | Speed |
|---|---|---|---|
| 8 GB | Qwen3 4B | 3.2 GB | ~35 tok/s |
| 16 GB | Qwen3 8B | 5.0 GB | ~25 tok/s |
| 24 GB | Qwen3 14B | 9.0 GB | ~20 tok/s |
| 32 GB+ | Qwen3 32B | 19.5 GB | ~12 tok/s |

You can override the auto-selection if you know what you're doing — it'll warn you, then let you proceed.

---

## What it's good at

**Coding**
- Reads your actual project files — not just what you paste in
- Writes, explains, refactors, and fixes bugs
- No token limit anxiety. No per-message cost.

**Security research**
- No content filters on exploit analysis, shellcode, payload breakdowns
- Nothing logged anywhere — your CTF notes stay yours
- Perfect for TryHackMe, HackTheBox, and offline lab environments
- Ask it to decode Burp output, analyse Nmap scans, write custom fuzzers

**Learning**
- Ask the same question ten ways at zero cost
- *"Explain this Metasploit module. Now simpler. Now with an example."*
- No judgment. No throttling. No *"I can't help with that."*

---

## Why this isn't ChatGPT

| | Cloud AI | your-local-agent |
|---|---|---|
| Your prompts stored | ✓ | ✗ |
| Content filtered | ✓ | ✗ |
| Works offline | ✗ | ✓ |
| Monthly cost | ✓ | ✗ |
| Reads your local files | ✗ | ✓ |
| Someone else's hardware | ✓ | ✗ |

---

## How it works under the hood

```
Your Mac
│
├── llama-server          ← runs the AI model using your M-series GPU
│     └── Qwen3 (4B–32B)  ← automatically chosen for your RAM
│
└── Aider                 ← reads your files, talks to the model,
      └── your terminal     answers in your project context
```

No Docker. No Python environment hell. No `.env` file you'll accidentally push to GitHub.

---

## Files created on your machine

```
~/models/
  └── Qwen3-*.gguf           the model (3–20 GB depending on RAM)

~/.local-ai/
  ├── setup.log              full timestamped log of every setup step
  ├── server.log             llama-server runtime output
  ├── state.json             what's installed (used by local-ai-update)
  └── bin/
      └── llama-server       the inference binary

~/.aider/
  └── config.json            Aider pointed at localhost:8080
```

---

## Repo structure

```
your-local-agent/
├── setup.sh            entrypoint — run once to install everything
├── update.sh           updater — run via local-ai-update
├── models.json         model registry — add new models here
└── lib/
    ├── detect.sh       reads your RAM, chip, disk, shell
    ├── install.sh      Homebrew + llama.cpp + Node.js + Aider
    ├── download.sh     model selection + download with resume
    ├── configure.sh    Aider config + shell aliases
    ├── parse_release.py  parses GitHub release JSON for llama.cpp
    └── verify.sh       starts server, sends test prompt, confirms
```

---

## Troubleshooting

### Setup failed — where do I look?

```bash
cat ~/.local-ai/setup.log
```

Every step is logged with a timestamp. Scroll to the last error.

---

### `command not found: local-ai-start`

Your shell aliases weren't loaded yet. Run:

```bash
source ~/.zshrc   # or source ~/.bash_profile
```

Then try `local-ai-start` again. If that doesn't work, check that setup completed without errors.

---

### `xcode-select: error: command line tools are already installed`

Not actually an error — this message means the tools are present. Setup will continue normally.

---

### Homebrew install fails or hangs

If you're behind a corporate proxy or a VPN is active, Homebrew's CDN can be blocked. Try:

```bash
# Disable proxy temporarily
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY

# Then re-run setup
bash setup.sh
```

---

### Model download stops or times out

Downloads are resumable. Just re-run:

```bash
bash setup.sh
```

Setup detects what's already done and skips it — only the download resumes.

---

### `llama-server: Bad CPU type in executable`

You're on an Intel Mac. This build targets Apple Silicon only. Intel support is on the roadmap — for now, this won't work on x86_64 Macs.

---

### `llama-server` won't start / port 8080 in use

Something else is already using port 8080. Find and kill it:

```bash
lsof -i :8080
kill -9 <PID>
```

Then run `local-ai-start` again.

---

### Aider can't connect to the model

Check the server is actually running:

```bash
local-ai-status
curl http://localhost:8080/health
```

If the server is down, start it:

```bash
local-ai-start
```

---

### `permission denied` running setup.sh

Make it executable first:

```bash
chmod +x setup.sh
bash setup.sh
```

---

### Out of disk space mid-download

Free up space, then re-run setup — the download will resume from where it left off:

```bash
df -h ~          # check how much free space you have
bash setup.sh    # resumes the download
```

---

## Updating

```bash
local-ai-update
```

Pulls the latest scripts, updates llama.cpp and Aider, and checks whether a better model is available for your RAM. If one is, it asks before downloading and removes the old one after to free up space.

---

## Security

The setup script was written with the following in mind:

- ✅ Command injection via user input — sanitised to `[a-zA-Z0-9-]` only
- ✅ Unsafe `rm` — path-guarded to `~/models/*` only, never outside
- ✅ `eval` of Homebrew path — validated against two known trusted paths
- ✅ Temp file race conditions — `chmod 600` immediately on creation
- ✅ Downloaded script permissions — `750` for scripts, `640` for config
- ✅ `set -euo pipefail` — in every script, fails fast and loud
- ✅ No hardcoded secrets — anywhere
- ⚠️ `curl | bash` — inherent to one-liner installers (Homebrew does this too). Mitigated: HTTPS only, GitHub raw source. Clone and inspect before running if you prefer.

---

## Roadmap

- [ ] Linux + NVIDIA CUDA support
- [ ] Intel Mac support
- [ ] Fish shell alias setup
- [ ] Open WebUI browser interface (chat UI on `localhost:3000`)
- [ ] Community benchmark table (model × chip × speed)

---

## Contributing

Most useful PRs:

- New models in `models.json` — add an entry with the right fields
- Bug reports for specific macOS versions or RAM configs
- Roadmap items — Linux, Intel, Fish shell

Test on your own machine before submitting.

---

<div align="center">

MIT License · Built for people who want their tools on their own hardware.

*Your prompts. Your model. Your machine.*

</div>
