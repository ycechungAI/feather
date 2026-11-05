---
id: morning-commute
name: Morning Commute Brief
model: "granite4:3b"
schedule: "30 7 * * *"
enabled: true
tools: [web_search, fetch_page]
timeout_minutes: 10
catchup: false
output:
  keep: 30
---

Fetch today's weather and traffic for your commute. Cover:

1. Current temperature, conditions, and chance of rain.
2. Major traffic incidents or delays on common routes.
3. Transit or school-bus advisories if any.
4. Dressing/commute recommendation.

Keep it short and actionable. Parent/son-focused.
