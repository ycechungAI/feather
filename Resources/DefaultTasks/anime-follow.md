---
id: anime-follow
name: anime-follow
schedule: "0 14 * * 6"
enabled: true
model: granite4:3b
next_run_at: ""
---

Adapted from noskill `anime-follow` (original: weekend follow run — download then file stages; cron 0 14,16,18,20 * * 6,0, missed once, notify os). FeatherA standalone uses a simplified compatible schedule and local Ollama prompt (no noskill/anime-tracker/transmission integration). Adjust with Sched for additional weekend times if desired.

What to do:
- Based on anime follow details I provide, list follow-up actions (check releases, download/file steps, status updates).
- Output a short checklist.

Provide context when running (followed shows, progress, links/notes):
