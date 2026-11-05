---
id: learning-digest
name: Learning Digest
model: "granite4:3b"
schedule: "0 20 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Find today's best free learning resources. Cover:

1. One new tutorial or course (coding, AI, or practical skill).
2. One article explaining a concept simply.
3. One practice project or exercise idea.
4. Where to find it (YouTube, blog, docs).

Son/AI-developer focused. Keep it actionable.
