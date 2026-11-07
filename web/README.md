# Cadre Web ◈

> *Lightweight, zero-runtime web surface and cockpit for Cadre autonomous AI teammates.*

Built with Svelte 5, Tailwind CSS 4, and [`@kleinbem/web-config`](https://github.com/kleinbem/web-config).

## ✨ Features

- **Fleet Design System**: Powered by `@kleinbem/web-config` with synchronized theme tokens, typography, and dark/light modes.
- **Teammates Cockpit**: Interactive overview of autonomous AI agent personas and their ACP tool privileges.
- **Live Pairing Console**: Chat and reasoning timeline with chain-of-thought folding and tool execution telemetry.
- **Fleet Compute Telemetry**: Real-time status for local Ollama nodes and distributed MeshLLM clusters with `<StatusDot />` indicators.
- **Command Palette (`⌘K` / `/`)**: Fast keyboard-driven fuzzy search across agents, views, models, and external fleet launchpads.

## 🛠️ Development

```bash
npm run dev      # Start local Vite development server
npm run check    # Run Svelte and TypeScript diagnostics
npm run build    # Build static SPA to build/
npm run preview  # Preview production build
```
