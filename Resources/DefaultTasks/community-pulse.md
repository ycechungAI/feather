---
id: community-pulse
name: Community Pulse
model: "granite4:3b"
schedule: "0 9 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Find today's local news and community events for your area. Cover:

1. Local government or school announcements.
2. Community events happening today or this weekend.
3. Public safety or traffic advisories.
4. One positive community story.

Provide 4–6 bullets with links. Parent/family-focused.
