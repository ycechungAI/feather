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

## Integration: call the existing local services (ADR-0017 pattern)

Feather doesn't copy noskill's, sched's or orcastrator's code. It calls the services that already run on this Mac over
`localhost` HTTP, the same way the noskill app does (noskill's ADR-0017). Each service keeps its own data and tests.

| Service | Port | Used for | Endpoints (checked in the noskill repo) |
|---|---|---|---|
| Ollama | 11434 | page Q&A with a 1B model | `POST /api/chat`, `GET /api/tags` |
| noskill agent | 11435 | skills, jobs, status, events | `POST /v1/chat/completions`, `POST /noskill/v1/jobs`, `POST /noskill/v1/jobs/draft`, `GET /noskill/v1/status`, `GET /noskill/v1/events` |
| sched (tasks) | 8787 | scheduled tasks | `GET/POST /api/tasks`, `POST /api/tasks/draft`, `POST /api/tasks/{id}/run`, `GET /api/runs/{id}/report` |
| research | macOS-native (see below) | search and research reports | chosen later; orcastrator is not used on macOS |

Routes are not hard-coded. They live in a user-editable file, `~/Library/Application Support/Feather/services.json`,
with the defaults above. When a service changes its routes, the user edits that file; Feather doesn't need a new build.

Rules: only `localhost`; if a service isn't running, Feather shows a clear message and starts nothing itself.

Research on macOS should use what macOS already provides, not orcastrator. Candidates to choose from:
- Apple's on-device Foundation Models framework (`SystemLanguageModel`, macOS 26 or later with Apple Intelligence on).
  Its API hasn't been checked on this Mac yet.
- Spotlight (`NSMetadataQuery`) to search files and saved pages on the Mac.
- Apple's Natural Language framework for summaries and keywords, without a model.

Web search itself still needs a source; this is an open choice.
Feather's new code is the browser side: the panel, the page text, and the forms. The services do the work.

## Models and routing (decided)

- **Three models, three jobs** (`services.json` keys in brackets):
  - **Router** `tev1:0.8b` [routerModel]: fast decisions, which tool or service handles a request.
  - **Answers** `granite4:3b` [answerModel]: page Q&A and summaries.
  - **Basic** `gemma3:1b` [basicModel]: search and simple agentic tasks.
- The router is `tev1:0.8b`, a fast decision model. It returns a route (`page_qa`, `search`, `schedule`, `none`) and a confidence. Below 0.5 confidence, or an unknown label, Feather asks the user instead of guessing. Tested live: a page-question with the page open routes to `page_qa` (0.67); a news search with no page routes to `none` at 0.31, which is why the threshold exists. It doesn't accept chat or generate calls. Noskill calls it through
  Ollama's `POST /v1/systemone` with JSON `{"model", "state", "questions", "keep_alive": -1}` (see noskill
  `internal/decide/jev.go`). Feather's router must use that same call, not a chat request.
- **Install choice (user decides):** Feather offers two ways to get Ollama:
  1. **Standalone:** the user installs Ollama from ollama.com; Feather only checks that it runs.
  2. **Integrated:** Feather downloads and updates Ollama itself, into `~/Library/Application Support/Feather/`.
  Both work the same way once the server answers on `127.0.0.1:11434`.

## Design direction (decided): Zen-style

The UI follows Zen Browser's approach: a calm, minimal window that gets out of the way.
- Vertical tab sidebar (collapsible), with pinned tabs and folders.
- Workspaces: separate tab sets for different work (for example research, coding, personal).
- Compact toolbar; the page gets most of the window.
- Keyboard-first: every action the assistant offers has a shortcut.
- The assistant lives in a side panel, not a popup, and it can be hidden.
- Split view and page preview are later steps, after the Q&A panel works.

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
