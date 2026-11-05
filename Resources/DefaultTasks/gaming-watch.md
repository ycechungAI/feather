---
id: gaming-watch
name: Gaming News Watch
model: "granite4:3b"
schedule: "0 12 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Check today's gaming news and releases. Cover:

1. New game releases or demos on Steam/consoles.
2. Major patch notes or updates for live-service games.
3. Gaming industry news (acquisitions, studio closures, delays).
4. Notable free-to-play or indie highlights.

Provide 4–6 bullets with links. Gaming-enthusiast focused.
