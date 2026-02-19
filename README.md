# 🦞 clawd-larvae

Ephemeral, disposable OpenClaw agents in Docker containers. Spawn them, give them a task, talk to them, kill them — their work persists after death.

Larvae are baby lobsters. They hatch, do their thing, and the results survive even after the container is gone.

## Quick Start

```bash
# 1. Build the larva image
docker build -t larva .

# 2. Spawn a larva
./larvae.sh spawn alice --model sonnet "Build a REST API for a todo app"

# 3. Talk to it (it remembers context)
./larvae.sh talk alice "Add authentication middleware"
./larvae.sh talk alice "Now write tests for everything"

# 4. Check on it
./larvae.sh status alice
./larvae.sh list

# 5. Kill it (files persist!)
./larvae.sh kill alice

# 6. Your code is still here
ls shared-workspace/alice/
```

## How It Works

```
┌──────────────────────────────────────────┐
│  Host Machine (macOS/Linux)              │
│                                          │
│  larvae.sh orchestrator                  │
│    ├── spawn: docker run → larva container
│    ├── talk:  docker exec → openclaw agent
│    ├── list:  show all running larvae    │
│    ├── kill:  docker stop (files stay)   │
│    └── status: health + workspace files  │
│                                          │
│  shared-workspace/                       │
│    ├── alice/    ← volume mount          │
│    ├── bob/      ← volume mount          │
│    └── charlie/  ← volume mount          │
│                                          │
│  ┌────────────┐  ┌────────────┐          │
│  │ larva-alice │  │ larva-bob  │  ...     │
│  │ (Docker)    │  │ (Docker)   │          │
│  │             │  │            │          │
│  │ OpenClaw    │  │ OpenClaw   │          │
│  │ Gateway     │  │ Gateway    │          │
│  │ + Agent     │  │ + Agent    │          │
│  │             │  │            │          │
│  │ /root/wksp  │  │ /root/wksp │          │
│  │  ↕ volume   │  │  ↕ volume  │          │
│  └────────────┘  └────────────┘          │
└──────────────────────────────────────────┘
```

Each larva is a Docker container running an OpenClaw gateway. The `larvae.sh` orchestrator:

1. **Spawns** a container with a volume-mounted workspace directory
2. **Talks** to the agent inside via `docker exec openclaw agent`
3. **Files persist** in `shared-workspace/<name>/` on the host even after the container is killed

The agent inside each container has full OpenClaw capabilities: file read/write, shell exec, web search, browser, etc. It's a complete AI coding agent in a box.

## Models

Use any model — cloud APIs or local Ollama:

| Shortcut   | Model                         | Notes                |
|------------|-------------------------------|----------------------|
| `opus`     | anthropic/claude-opus-4-6     | Most capable, $$     |
| `sonnet`   | anthropic/claude-sonnet-4-5   | Fast + smart (default)|
| `gpt`      | openai/gpt-5.2               | OpenAI flagship      |
| `qwen`     | ollama/qwen3-next:80b         | Local, free          |
| `devstral` | ollama/devstral:latest        | Local, code-focused  |
| `deepseek` | ollama/deepseek-r1:70b        | Local, reasoning     |
| `llama`    | ollama/llama3.3:latest        | Local, general       |
| `coder`    | ollama/qwen2.5-coder:32b      | Local, code-focused  |

```bash
# Cloud models (need API keys)
./larvae.sh spawn smart-worker --model opus "Architect a microservices system"

# Local models (need Ollama running on host)
./larvae.sh spawn local-worker --model coder "Refactor this Python module"

# Full model strings work too
./larvae.sh spawn custom --model anthropic/claude-sonnet-4-5 "Do something"
```

## Commands

```bash
./larvae.sh spawn <name> [--model <m>] [--workspace <dir>] "task"
./larvae.sh list
./larvae.sh talk <name> "message"
./larvae.sh status <name>
./larvae.sh logs <name> [lines]
./larvae.sh kill <name>
./larvae.sh killall
```

## Requirements

- Docker
- API key(s) as environment variables:
  - `ANTHROPIC_API_KEY` — for Claude models
  - `OPENAI_API_KEY` — for GPT models
  - Ollama models connect to `host.docker.internal:11434` (Ollama running on host)

## Custom Workspace

Point a larva at any directory on your machine:

```bash
# Work on an existing project
./larvae.sh spawn reviewer --model sonnet --workspace ~/projects/my-app "Review the codebase and suggest improvements"

# The larva can read/write files in ~/projects/my-app
./larvae.sh talk reviewer "What did you find? Any security issues?"
```

## Multi-Larva Workflows

Spawn multiple larvae for parallel or collaborative work:

```bash
# Architect designs, coder implements, reviewer checks
./larvae.sh spawn architect --model opus "Design a real-time chat system architecture"
./larvae.sh spawn coder --model sonnet "Implement the WebSocket server"
./larvae.sh spawn reviewer --model sonnet "Review the code for security issues"

# Check on everyone
./larvae.sh list

# Kill them all when done
./larvae.sh killall
```

## How OpenClaw Orchestrates Larvae

The parent OpenClaw instance (the one you're chatting with) can spawn and manage larvae on your behalf. Just say:

> "Spawn a larva named alice on sonnet to build a REST API"
> "Check on alice"
> "Tell bob to add unit tests"
> "Kill all larvae"

The parent runs `larvae.sh` commands via shell exec and relays the results back to you.

## Architecture

- **Image**: `larva` — Node 22 slim + OpenClaw pre-installed (~200MB)
- **Config**: `openclaw.json` baked into image, model overridden at spawn time
- **Networking**: Each larva gets a unique host port (28700+) mapped to internal port 18789
- **Storage**: Volume mount from `shared-workspace/<name>/` → `/root/workspace`
- **Communication**: `docker exec openclaw agent --local` with session persistence
- **Isolation**: Each container is fully isolated with its own filesystem, processes, and network

## License

MIT
