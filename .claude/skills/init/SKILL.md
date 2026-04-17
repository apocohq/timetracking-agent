---
name: init
description: Initialize the timetracking config by collecting the user's GitHub handle, the list of repositories to track, and mapping each repo to a Toggl project. Confirms with the user and writes the result to USER.md. Use when the user says "init", "setup", "configure timetracking", or when USER.md is missing and the user wants to get started.
---

# Init Timetracking Config

Collect the user's GitHub handle, tracked repositories, and a mapping from each repo to a Toggl project, then persist it to `USER.md`.

The Toggl API token is injected at the HTTP layer — use the literal placeholder `$TOGGL_API_TOKEN` in curl commands and do not prompt the user for it.

## Steps

1. **Check existing config.** If `USER.md` already exists in the project root, show the user its current contents and ask whether to overwrite. If they decline, stop.

2. **Detect the GitHub handle** via `gh auth status`:

   ```bash
   gh api user --jq .login
   ```

   Use the returned login as the handle. If `gh` is not authenticated, tell the user to run `gh auth login` and stop.

3. **Propose repositories from recent activity.** Find distinct repos where the user has committed or opened/reviewed PRs in the past week:

   ```bash
   START=$(date -v-7d -u +%Y-%m-%d)   # macOS; use `date -d '-7 days'` on Linux
   gh search commits --author "<handle>" --committer-date ">=$START" \
     --json repository --jq '.[].repository.nameWithOwner' | sort -u
   gh search prs --author "<handle>" --updated ">=$START" \
     --json repository --jq '.[].repository.nameWithOwner' | sort -u
   ```

   Merge and dedupe the `owner/name` results. Show the list to the user and use `AskUserQuestion`:
   - question: "Track these repos? (pick one)"
   - options: "Use all", "Pick a subset", "Add more", "Enter manually"

   - **Use all** → take every proposed repo.
   - **Pick a subset** → follow up with free-form `"Which to drop? (comma-separated)"` and remove those.
   - **Add more** → follow up with free-form `"Additional repos (owner/name, comma-separated)"` and append.
   - **Enter manually** → follow up with free-form `"Which repositories do you want to track? (owner/name, one per line or comma-separated)"`.

   If the proposal query returns zero repos, skip straight to the manual prompt.

4. **Validate repos.** Each entry must match `owner/name`; if any don't, ask the user to re-supply just those.

5. **Discover Toggl workspace id.**

   ```bash
   curl -s -u "$TOGGL_API_TOKEN:api_token" \
     https://api.track.toggl.com/api/v9/me
   ```

   Extract `default_workspace_id` from the JSON.

6. **Fetch Toggl projects** for the workspace:

   ```bash
   curl -s -u "$TOGGL_API_TOKEN:api_token" \
     "https://api.track.toggl.com/api/v9/workspaces/<workspace_id>/projects?active=true"
   ```

   Keep `id` and `name` for each project. If the list is empty, tell the user to create at least one Toggl project and stop.

7. **Map each repo to a Toggl project.** For every parsed repo, use `AskUserQuestion`:
   - question: `"Which Toggl project should '<owner/repo>' map to?"`
   - options: one per Toggl project name (label = project name), plus a final "Skip (no project)" option.
   - Record the chosen `project_id` (or `null` for skip) alongside the repo.

   If there are more projects than `AskUserQuestion` can show as options at once, page through them (e.g. "More projects…" option that re-asks with the next batch).

8. **Show for approval.** Present a summary:

   ```
   GitHub handle: <handle>
   Tracked repositories:
     - owner/repo1 -> Toggl: <Project Name> (id: 12345)
     - owner/repo2 -> Toggl: <Project Name> (id: 67890)
     - owner/repo3 -> Toggl: (none)
   ```

   Use `AskUserQuestion` with options like "Approve", "Edit repos", "Remap projects", "Cancel". Loop back to the relevant step if they want edits. Stop if they cancel.

9. **Write `USER.md`** in the project root using this exact template:

   ```markdown
   # User Config

   ## GitHub Handle
   <handle>

   ## Toggl Workspace
   <workspace_id>

   ## Tracked Repositories
   - owner/repo1 -> toggl:12345 (Project Name)
   - owner/repo2 -> toggl:67890 (Project Name)
   - owner/repo3 -> toggl:none
   ```

   The `-> toggl:<id> (<name>)` suffix is the machine-readable mapping. Use `toggl:none` when the user skipped mapping.

10. **Gitignore `USER.md`.** Ensure `.gitignore` in the project root contains a line `USER.md`. Create `.gitignore` if missing. Only append if the entry isn't already there.

11. **Confirm** to the user that `USER.md` was written and is gitignored.
