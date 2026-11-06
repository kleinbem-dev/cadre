# Cadre ◈ Branding & Identity

> **Private AI teammates on your own compute.**

---

## 1. Core Essence

* **Name:** `cadre` (lowercase, unpretentious, pairs directly with `revue`)
* **Glyph:** `◈` (the framed spark / white diamond)
* **Mark:** `[ ◈ ]` (the corner frame enclosing autonomous intelligence)
* **Tagline:** *Private AI teammates on your own compute.*
* **Subtitle:** Self-hosted AI agents powered by Goose over ACP, backed by your choice of local inference (Ollama, Mesh-LLM, llama-server).

---

## 2. Visual Identity

### Assets
* **Avatar (`assets/avatar.svg`):** 256×256 icon designed for Buzz chat, Nostr pubkey avatars, and GitHub profile icons.
* **Header Logo (`assets/logo.svg`):** Widescreen banner for GitHub README headers and documentation.

### Palette

| Role | Color Name | Hex Code | Purpose |
| :--- | :--- | :--- | :--- |
| **Canvas** | Deep Slate | `#0b0f19` | Dark mode terminal/readiness |
| **Surface** | Dark Charcoal | `#111827` | Card backgrounds, UI tiles |
| **Frame** | Steel / Silver | `#94a3b8` | Corner brackets (the architectural frame) |
| **Accent / Intelligence** | Warm Amber | `#f59e0b` | The central spark, activity badges, mentions |
| **Text Primary** | Crisp White | `#f8fafc` | Headlines and titles |
| **Text Muted** | Slate Gray | `#94a3b8` | Subtitles, descriptions, flags |

---

## 3. The Ecosystem Pair

| Tool | Symbol | Role | Metaphor |
| :--- | :---: | :--- | :--- |
| **`revue`** | 🎭 | Automated AI Code Review & CI | The theatrical inspector / stage review |
| **`cadre`** | ◈ | Autonomous AI Teammates & Agents | The core crew / operational framework |

---

## 4. Personas & Surfaces

### In Team Chat (`@cadre`)
* **Handle:** `@cadre`
* **Avatar:** `assets/avatar.svg` (amber spark inside steel brackets)
* **Tone:** Direct, capable, collegial, concise.
* **Footer convention:** *(Goose via ACP · Ollama local)* or *(Goose via ACP · MeshLLM cluster)*

### In the Terminal
```bash
$ nix run github:kleinbem/cadre -- --help
cadre ◈ private AI teammates on your own compute

Usage: cadre [OPTIONS]

Options:
  --backend <ENGINE>  Inference runner: auto | mesh | ollama [default: auto]
  --model <MODEL>     Model to serve/query [default: Qwen3-8B-Q4_K_M]
  --port <PORT>       API port [default: 9337]
```
