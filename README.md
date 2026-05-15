# flash

A lightweight shell-based AI agent framework. Uses bash scripts to define tools and communicates with LLMs via an API.

## Usage

```bash
./agent.sh
```

Configure models and API endpoint in `config.sh` or via environment variables:

- `MODEL_E2B` — Model for the main agent
- `MODEL_E4B` — Model for sub-agents
- `API_URL` — Ollama API endpoint (default: `http://localhost:11434/api/chat`)

## Tools

Tools are standalone shell scripts in the `tools/` directory that extend the agent's capabilities.

## Docker

```bash
docker build -t flash .
docker run flash
```
