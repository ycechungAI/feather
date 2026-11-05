---
id: research-paper-digest
name: AI Research Paper Digest
model: "granite4:3b"
schedule: "0 8 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Fetch today's new arXiv papers in cs.AI and cs.LG. Summarize:

1. 2–3 most relevant papers with title, authors, one-line takeaway.
2. Why each matters to a developer building with local LLMs.
3. Links to arXiv abstract and any GitHub code.

Keep it under 200 words. Developer-focused.
