# Ollama Setup (FeatherA, local-only, no sudo)

FeatherA 0.3.0 uses **local Ollama** for Ask/Agents/Tasks/Research.

## Quick setup (recommended)
From the repo:

```bash
scripts/setup.sh
```

This (non-admin flow) installs/starts Ollama in `~/Applications` (no sudo) and can auto-pull recommended models.

Useful options:
```bash
scripts/setup.sh --install-ollama   # install Ollama
scripts/setup.sh --restart          # restart Ollama
scripts/setup.sh --pull-models      # pull recommended models
```

## Recommended models
- `tev1:0.8b` — router/basic tasks
- `granite4:3b` — answers & Research default (**never 1B auto-select**)
- `nomic-embed-text:latest` — optional (if used by workflows)

Manual pull:
```bash
ollama pull tev1:0.8b
ollama pull granite4:3b
```

## Verify
```bash
curl http://127.0.0.1:11434/api/version
ollama list
```

## Notes
- FeatherA (sandboxed) may not execute external CLI tools directly; in-app pulls use the Ollama HTTP API where implemented. Use `scripts/setup.sh` if in-app pull is blocked.
- If Research shows connection/model issues, check **AI panel → `>>` Logs** and ensure Ollama is running.
