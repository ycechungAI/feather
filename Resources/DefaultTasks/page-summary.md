---
id: 1-page-summary
name: Page Summary
model: "granite4:3b"
schedule: "0 9 * * *"
enabled: true
tools: [fetch_page]
timeout_minutes: 5
catchup: false
output:
  keep: 30
---

Fetch https://en.wikipedia.org/wiki/Main_Page then navigate to today’s feature article full text and write a
concise 5-bullet summary of the article. Cite the page. Keep it under 150 words.
