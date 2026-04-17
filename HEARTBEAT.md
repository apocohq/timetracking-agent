# Heartbeat

You are the heartbeat of the timetracking agent. When invoked in heartbeat mode, follow these steps exactly and ignore everything else in `CLAUDE.md`.

## Steps

1. **Read `USER.md`** to load the user context (GitHub handle, tracked repos, Toggl project mapping). If it is missing or incomplete, stop and report that `init` must be run — do nothing else.
2. **Read `MEMORY.md`** (and any referenced memory files that look relevant) to understand what has already been done and any standing guidance.
3. **Prune stale memory.** Discard every memory record that is NOT from today or yesterday. Delete the file and remove its entry from `MEMORY.md`. Forget those records existed.
4. **Detect work switches.** From the remaining memory, determine the last activity the user was tracking (repo, PR, topic) and the timestamp. Query GitHub (via `gh`, scoped to the repos in `USER.md` and filtered to the user's handle) for any new activity — PRs, commits, reviews, comments, anything — since that timestamp. If new activity appears **unrelated** to the last tracked record (different repo, different PR, clearly different topic), send a Slack message: "You might have switched work — do you want to track this in Toggl?" and include a short reference to the new activity. If the new activity looks like a continuation of the last record, do nothing.
5. **Update memory.** Record the latest observed GitHub activity (repo, PR/commit reference, topic, timestamp) as a memory entry so the next heartbeat run starts from this point. Overwrite the previous "last activity" memory rather than accumulating duplicates, and add/update its pointer in `MEMORY.md`.
