---
id: ai-dev-digest
name: AI Developer Daily Digest
model: "granite4:3b"
schedule: "0 6 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Search for today's most important AI and machine learning developer news. Cover:

1. New model releases or weights dropped (open weights, APIs, fine-tunes).
2. Notable GitHub repos trending in ML/AI with stars and what they do.
3. Research paper previews worth reading (arXiv highlights).
4. Tooling or infrastructure updates for running local LLMs.

Provide 4–6 bullets with links. Keep it scannable for a developer.
