---
id: personal-finance
name: Personal Finance Pulse
model: "granite4:3b"
schedule: "0 18 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Summarize today's personal-finance relevant news. Cover:

1. Crypto or major asset moves.
2. One budgeting or saving tip.
3. One scam/fraud alert to watch for.
4. One rate or fee change (bank, card, loan).

Investor/father-focused. Concise and practical.
