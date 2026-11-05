---
id: market-movers
name: Market Movers Brief
model: "granite4:3b"
schedule: "0 16 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Summarize today's US market action at the close. Cover:

1. Dow, S&P 500, Nasdaq moves and key drivers.
2. Top gainers/losers with brief reasons (earnings, news, sentiment).
3. Sector rotation (what's hot, what's not).
4. Crypto or macro headline if it moved equities.

Provide 4–6 bullets with links. Investor-focused, concise.
