---
name: red-larvae
description: Spawn and manage ephemeral OpenClaw Docker agents ("larvae"). Use when you need to run isolated coding tasks, spin up disposable AI workers, orchestrate parallel agents, or delegate work to containerized OpenClaw instances. Triggers on requests like "spawn a larva", "spin up a container to do X", "run that in a larvae", or multi-agent Docker workflows.
---

# red-larvae

Ephemeral OpenClaw agents in Docker containers. Spawn, talk, kill — work persists.

## Setup

Resolve all paths relative to this skill's directory: `SKILL_DIR`.

```bash
cd SKILL_DIR
docker build -t larva .
```

Requires `ANTHROPIC_API_KEY` (and optionally `OPENAI_API_KEY`) in env. For local Ollama models, Ollama must be running on the host.

## Spawning a Larva

```bash
SKILL_DIR/larvae.sh spawn <name> --model <model> "initial task"
```

Model shortcuts: `opus`, `sonnet` (default), `gpt`, `qwen`, `devstral`, `deepseek`, `llama`, `coder`. Full model strings also accepted.

Each larva gets its own workspace at `SKILL_DIR/shared-workspace/<name>/`. Use `--workspace <dir>` to point at a custom host directory.

## Talking to a Larva

```bash
SKILL_DIR/larvae.sh talk <name> "message"
```

Larvae maintain conversation context across messages. They are full OpenClaw agents with file, exec, web, and browser tools.

## Management

```bash
SKILL_DIR/larvae.sh list              # All larvae with status
SKILL_DIR/larvae.sh status <name>     # Detailed info + workspace files
SKILL_DIR/larvae.sh logs <name>       # Container logs
SKILL_DIR/larvae.sh kill <name>       # Stop container, files persist
SKILL_DIR/larvae.sh killall           # Stop all
```

## Key Behaviors

- Files written to `/root/workspace` inside the container persist on the host in `shared-workspace/<name>/`
- Each larva runs its own OpenClaw gateway on a unique port (28700+)
- Communication uses `docker exec openclaw agent --local --agent larva`
- Killing a larva stops the container but preserves all workspace files
- Local Ollama models connect via `host.docker.internal:11434`

## Multi-Larva Pattern

Spawn multiple for parallel work:

```bash
SKILL_DIR/larvae.sh spawn architect --model opus "Design the system"
SKILL_DIR/larvae.sh spawn coder --model sonnet "Implement it"
SKILL_DIR/larvae.sh spawn tester --model coder "Write tests"
```
