---
name: log-github-activity
description: Pull the user's recent GitHub activity from tracked repositories and create matching Toggl time entries. Use when the user says "log my work", "log today", "track github to toggl", or asks to record recent PRs/commits as time entries.
---

# Log GitHub Activity to Toggl

Fetch the user's recent GitHub activity from repos listed in `USER.md`, let the user review and estimate durations, then POST the approved items as Toggl time entries.

The Toggl API token is injected at the HTTP layer — use the literal placeholder `$TOGGL_API_TOKEN` in curl commands and do not prompt the user for it. The workspace id is discovered at runtime via `GET /me`.

## Steps

1. **Load config.** Read `USER.md`. If missing or the GitHub handle / repos list is empty, stop and tell the user to run the `init` skill.

   Parse each repo line. The format is `- owner/repo -> toggl:<id> (<name>)` or `- owner/repo -> toggl:none`. Build an in-memory map `{ "owner/repo": <project_id or null> }`. If a repo line lacks the `-> toggl:...` suffix, treat its mapping as `null` and warn the user they should re-run `init` to map it.

2. **Pick time range.** Use `AskUserQuestion`:
   - question: "What time range should I pull activity for?"
   - options: "Today", "Yesterday", "This week", "Custom range"
   - For "Custom range", follow up with a free-form question asking for `YYYY-MM-DD..YYYY-MM-DD` and parse it.
   - Convert the choice to an ISO start/end pair in the user's local timezone. "Today" = 00:00 local today through now.

3. **Discover workspace id.** Call Toggl `/me` once to get the default workspace id:

   ```bash
   curl -s -u "$TOGGL_API_TOKEN:api_token" \
     https://api.track.toggl.com/api/v9/me
   ```

   Extract `default_workspace_id` from the JSON. Cache it in memory for this session.

4. **Pull GitHub activity.** For each repo in `USER.md`, run the queries below with the time range from step 2. Use `gh` CLI, filtered by the user's handle.

   - **Merged / authored PRs:**
     ```bash
     gh pr list --repo <owner/repo> --author <handle> --state all \
       --search "updated:>=<start>" \
       --json number,title,url,updatedAt,state,mergedAt
     ```
   - **Commits authored in the range:**
     ```bash
     gh search commits --author <handle> --repo <owner/repo> \
       --committer-date ">=<start>" \
       --json sha,commit,url
     ```
   - **Review activity (optional but useful):**
     ```bash
     gh search prs --reviewed-by <handle> --repo <owner/repo> \
       --updated ">=<start>" --json number,title,url,updatedAt
     ```

   Deduplicate: if a PR and its commits both appear, prefer the PR and drop commits whose message matches a commit in that PR.

5. **Build candidate entries.** For each unique item produce:
   - `description`: PR title, or commit message first line, or `"Review: <pr title>"`.
   - `start`: item's `updatedAt` / commit `committedDate`, rounded to the nearest 15 min.
   - `duration_seconds`: initial estimate — 30 min for a commit, 60 min for a PR, 15 min for a review. These are starting points for the user to edit.
   - `tags`: `[<repo-name>]`.
   - `url`: for display only.

6. **Review with the user.** Present a numbered list:

   ```
   1. [owner/repo1 → Toggl: Project A] PR #42 "Add foo" — 60m, start 09:15
   2. [owner/repo2 → Toggl: (none)] commit 3f1a2b "Fix bar" — 30m, start 11:00
   ...
   ```

   Ask via `AskUserQuestion`: "Log all as shown / Edit durations / Drop some / Cancel". If the user picks edit or drop, collect the adjustments in a follow-up free-form question (e.g. `1=90m, 3=skip`) and reapply.

7. **Post entries to Toggl.** For each approved entry, POST to the workspace:

   ```bash
   curl -s -u "$TOGGL_API_TOKEN:api_token" \
     -H "Content-Type: application/json" \
     -X POST \
     "https://api.track.toggl.com/api/v9/workspaces/<workspace_id>/time_entries" \
     -d '{
       "created_with": "timetracking-agent",
       "description": "<description>",
       "start": "<start ISO8601 with local offset, e.g. 2026-04-17T06:45:00+02:00>",
       "duration": <duration_seconds>,
       "tags": ["<repo>"],
       "project_id": <project_id>,
       "workspace_id": <workspace_id>
     }'
   ```

   Look up the `project_id` for the entry's repo from the mapping parsed in step 1. Omit the `project_id` field entirely if the mapping is `null` (skipped).

   Notes:
   - `duration` is in seconds. For completed entries use a positive value; Toggl will derive `stop` from `start + duration`.
   - **Timezone:** the times shown to the user in step 6 are local wall-clock. When serializing `start`, send the local time with its explicit offset (e.g. `+02:00`) — or equivalently, convert local → UTC and append `Z`. Never take the local wall-clock digits and append `Z` directly; that mislabels local time as UTC and Toggl will render it shifted by the offset. Get the current offset with `date +%z` (e.g. `+0200` → format as `+02:00`).
   - Run POSTs sequentially so failures are easy to attribute. If one fails, report which and continue with the rest.

8. **Report results.** Print a compact summary:

   ```
   Logged 4 entries to Toggl (workspace 12345):
     ✓ PR #42 "Add foo" — 60m
     ✓ commit 3f1a2b "Fix bar" — 30m
     ✗ Review: PR #17 — HTTP 400 (body: ...)
   ```

   Include the `id` of each created entry if available so the user can delete them from Toggl if needed.

## Guardrails

- Never invent GitHub activity — only log items returned by `gh`.
- Never hardcode or echo the token. Use `$TOGGL_API_TOKEN` as a literal placeholder.
- If the time range yields zero items, say so and stop — do not create empty entries.
- If `GET /me` fails, stop before touching time entries and surface the HTTP status.
