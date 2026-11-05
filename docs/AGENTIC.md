# Experiment: agentic Feather

Branch `experiment/agentic`, macOS only. This branch is allowed to get bigger and slower than `main`. It is a
research branch: it proves whether a small local model and noskill can run inside the browser. If it works, the
useful parts are merged back into a careful design. `main` stays the small, fast browser.

## Goal

Integrate parts of noskill into Feather and rework them for the browser, so a local model can help with the page
the user is looking at.

## First experiment (what this branch must prove)

1. A small local model (about 1B parameters, through Ollama on `127.0.0.1:11434`) answers a question about the
   current page's text. No network calls except to the local Ollama server.
2. The page text is extracted from the active tab and given to the model, with a size limit.
3. The answer appears in a small panel next to the page. Nothing is saved or sent anywhere else.

Second step, after the first works: call noskill's local API (`127.0.0.1:11435`) to run a skill on the page.

## Features

Must have:
- **Schedule tasks**: run a task on a schedule, such as "every morning, summarise the news I saved". Built on noskill's
  scheduler (`apps/scheduler`, sched), not a new scheduler.
- **Search and research**: search the web and produce a sourced report. Built on noskill's research tooling
  (`apps/orcastrator`, STORM-style reports), with citations the user can check.

Nice to have:
- **Self-healing**: detect a broken page or failed task, retry, or ask the user to fix it. Noskill's healer is the
  model for this.
- **Agentic coding**: a coding helper for the page the user is working on (for example a GitHub or docs page).

Order: first the page Q&A experiment (above), then search and research, then scheduled tasks, then the nice-to-haves.

## Constraints

- Local only: no telemetry, no accounts, no cloud model calls. The browser's own privacy rules still apply.
- Each addition is measured: app size, memory and time to first page, against `main`. The numbers go in this file.
- Ollama and noskill are external processes. The browser doesn't start or stop them; it shows a clear message
  when they aren't running.
- Speed and memory are judged against the budget in featherWIN's decision log (speed wins only inside the budget);
  here the budget is relaxed on purpose, and every increase is recorded.

## Open questions

- Which 1B model to use (the noskill recommended model list has `gemma3:1b`; check its size and quality on pages).
- Where the page text comes from (WebKit JavaScript, `WKWebView` evaluate, size limit).
- Whether noskill is linked in, or called as a separate local service (the second is simpler and keeps the browser small).

## Measurements

_None yet._
