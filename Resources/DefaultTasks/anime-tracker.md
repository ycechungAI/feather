---
id: anime-tracker
name: Anime Release Tracker
model: "granite4:3b"
schedule: "0 10 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Check for new anime episodes released today or tomorrow and upcoming seasonal announcements. Cover:

1. New episodes of currently airing shows.
2. New season premieres announced this week.
3. Notable movie or OVA releases.
4. Streaming platform availability notes.

Provide 4–6 bullets with links. Anime-lover focused.
