# GraphQL Queries for PR Review Threads

**IMPORTANT:** Always inline the GraphQL query directly in the `gh api graphql` command. Do NOT write queries to temp files and use `$(cat /tmp/...)` — command substitution (`$(...)`) triggers security permission prompts that block autonomous execution.

## Two-Phase Query Strategy

To avoid filling context with large comment bodies from resolved threads, use a **two-phase approach**:

1. **Phase 1 — Metadata only:** Fetch all threads with path, line, resolved status, and thread IDs. No comment bodies. Only fetches the first comment's author (for attribution).
2. **Phase 2 — Full bodies for unresolved threads only:** Use the `node` interface to fetch full comment bodies ONLY for unresolved thread IDs collected in Phase 1.

This prevents resolved thread bodies (often 3–4KB each from bot reviewers) from consuming context.

---

## Phase 1: Fetch thread metadata (no comment bodies)

Use `gh api graphql --input -` with a heredoc to avoid shell `$` interpolation issues:

```bash
cat <<'QUERY_EOF' | gh api graphql --input -
{"query":"query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){title number url author{login}baseRefName headRefName reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id isResolved isOutdated path line startLine diffSide resolvedBy{login}comments(first:1){totalCount nodes{author{login ...on Bot{id}}}}}}}}}","variables":{"owner":"{owner}","repo":"{repo}","number":{number}}}
QUERY_EOF
```

Replace `{owner}`, `{repo}`, and `{number}` with actual values inline.

**This returns for each thread:**
- `id` — needed for Phase 2 node query
- `isResolved`, `isOutdated` — for categorization
- `path`, `line`, `startLine` — file location
- `resolvedBy` — who resolved it
- `comments.totalCount` — how many comments in the thread
- `comments.nodes[0].author` — who started the thread (first comment only, no body)

**Pagination:** If `pageInfo.hasNextPage` is `true`, re-run with `$cursor` set to `endCursor`. Repeat until `hasNextPage` is `false`.

---

## Phase 2: Fetch full comments for unresolved threads

After Phase 1, collect the `id` values of all **unresolved** threads (where `isResolved` is `false`).

Build a batched `node` query using aliases. Example with 2 unresolved threads:

```bash
cat <<'QUERY_EOF' | gh api graphql --input -
{"query":"{thread0:node(id:\"PRRT_abc123\"){...on PullRequestReviewThread{comments(first:50){nodes{id body author{login ...on Bot{id}}createdAt updatedAt url}}}} thread1:node(id:\"PRRT_def456\"){...on PullRequestReviewThread{comments(first:50){nodes{id body author{login ...on Bot{id}}createdAt updatedAt url}}}}}"}
QUERY_EOF
```

**How to construct this query:**
1. Read the Phase 1 output and identify unresolved thread IDs
2. For each unresolved thread, create an alias `thread0`, `thread1`, `thread2`, etc.
3. Each alias queries `node(id:"THREAD_ID")` with the full comments fragment
4. Combine all aliases into a single query string
5. Inline the query in the heredoc — do NOT use `$(...)` or `${...}`

**If there are zero unresolved threads, skip Phase 2 entirely.**

**If there are more than 20 unresolved threads**, split into batches of 20 per query to avoid hitting GitHub's query complexity limits.

---

## Resolved thread summaries (from Phase 1 data only)

For resolved threads, you have enough from Phase 1 to write the report line:

```
- ✅ **{path}:{line}** — {summarize from path/line context} *(resolved by @{resolvedBy})*
```

Do NOT fetch full comment bodies for resolved threads. Use the file path, line number, and your knowledge of the PR to write a brief summary.

---

## Fetch general PR discussion comments (issue comments)

These are top-level PR comments not attached to specific code lines:

```bash
gh api repos/{owner}/{repo}/issues/{number}/comments --paginate
```

Include these in the report under a separate "General Discussion" section if they contain actionable feedback (skip bot-generated status comments, CI notifications, etc.).

## Identifying bot comments

A comment author is a bot if:
- The GraphQL `__typename` is `Bot`
- The REST `user.type` is `"Bot"`
- The login ends in `[bot]` (e.g., `dependabot[bot]`)

Label bot comments in the report as `[bot]` next to the author name.
