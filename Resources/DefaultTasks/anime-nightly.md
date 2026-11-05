---
id: anime-nightly
name: anime-nightly
schedule: "30 2 * * *"
enabled: true
model: granite4:3b
next_run_at: ""
---

Adapted from noskill `anime-nightly` (original: scheduled anime-tracker run "all stages", cron 30 2 * * *, missed once, notify os). FeatherA standalone runs this as a local Ollama prompt (no noskill/anime-tracker service integration).

What to do:
- Review anime tracker state/notes I provide and summarize nightly status: what to check/download/file, any issues, and next actions.
- Keep it concise and actionable.

Provide context when running (tracker state, shows, files/episodes, errors):
