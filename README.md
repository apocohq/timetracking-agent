# Timetracking Agent

A Claude Code agent that turns your GitHub activity into Toggl time entries.

It reads a per-user config ([USER.md](USER.md), gitignored), pulls recent PRs, commits, and reviews from the repos you track, lets you review/adjust durations, and logs them to Toggl.

## What it does

- **[init](.claude/skills/init/SKILL.md)** — interactive setup. Detects your GitHub handle via `gh`, proposes repos from your recent activity, maps each repo to a Toggl project, and writes [USER.md](USER.md).
- **[log-github-activity](.claude/skills/log-github-activity/SKILL.md)** — pulls your GitHub activity for a chosen time range (today / yesterday / this week / custom), builds candidate time entries with sensible default durations, and posts the approved ones to Toggl.
- **[heartbeat](HEARTBEAT.md)** — background mode that detects when you've switched work (new repo / PR / topic) and nudges you on Slack to track the switch. Prunes stale memory each run.

## How it works

- **GitHub** access via the `gh` CLI, scoped to repos in [USER.md](USER.md) and filtered to your handle.
- **Toggl** access via the v9 REST API. The API token is injected at the HTTP layer as `$TOGGL_API_TOKEN` — never prompted or echoed. The workspace id is discovered at runtime from `GET /me`.
- **Config** lives in [USER.md](USER.md) (GitHub handle, workspace id, `repo -> toggl project` mapping).
- **Heartbeat state** is persisted via Claude's built-in memory tool (under a `heartbeat/last_activity` key) so each run can spot work switches since the last observation.

## Getting started

Tell the agent `init` to create [USER.md](USER.md), then `log my work` (or `log today` / `log this week`) to push entries to Toggl.
