---
id: diskwatch
name: diskwatch
schedule: "manual"
enabled: true
model: granite4:3b
next_run_at: ""
---

Adapted from noskill `diskwatch` (original: model-free chore that checks volumes against disk-watch limits and alerts on low space). FeatherA standalone safety boundary: **no autonomous browser/agent disk control or scanning**.

What to do (prompt-only):
- Analyze disk usage information I paste (e.g., `df -h`, volume free space, folder sizes) and report whether any drive looks low on space.
- Give clear, safe recommendations. Do not claim to have checked disks yourself.

Paste disk info when running:
