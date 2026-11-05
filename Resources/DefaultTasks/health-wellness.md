---
id: health-wellness
name: Health & Wellness Brief
model: "granite4:3b"
schedule: "0 19 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Find today's health and wellness items. Cover:

1. One exercise or movement tip (10 min or less).
2. One nutrition or meal idea.
3. One sleep or stress-management note.
4. One public-health advisory if relevant.

Parent/father-focused. Safe, general advice only.
