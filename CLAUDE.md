## How we work here

- **Words and decisions.** The domain's words are in `docs/GLOSSARY.md` and the architecture decisions in `docs/adr/`. Use the glossary's terms in code, interface copy and pull requests. A change to a term or a decision updates its file in the same pull request.
- **Phases.** Work of more than one step goes plan, execute, test, review: one pull request per phase, made of small commits whose subjects are plain sentences (see `git log`). The iOS port's rules are in `ios/PLAN.md`. Read `ios/ui-parity/PLAN.md` before changing any iOS screen: the iPhone app takes the Android app's shape (ADR 0003).
- **Pull requests target `main`.** Branch each phase from `origin/main`. Stacked pull requests failed here once: two were merged into their stacked base, and the work never reached `main`. After a merge, confirm it with `git merge-base --is-ancestor <head> origin/main`.
- **Attribution.** Commits and pull requests carry the author's words only: no co-author trailer, no "Generated with" line, no session link. `.claude/settings.json` and `.githooks/commit-msg` enforce this.
- **Other people's work.** Treat uncommitted changes in the working tree as the owner's, whoever you think wrote them, and ask before reverting, stashing or deleting them. Delete only the branches you created, one by one, by name.
- **The glass look has no blur**, on either platform, by design. Android cannot blur a live camera preview at its minimum SDK, and both apps keep one look.

### In a cloud session

A cloud session runs on Linux with Docker, JDK 21 and Python, and without Swift, Xcode, the Android SDK or a phone.

- **CindyCore** (the Swift engine and page models): `docker run --rm -v "$PWD":/w -w /w swift:6.1.2-noble swift test --package-path ios/CindyCore`. This is the image the Linux CI job uses.
- **The iOS app, its UI tests, and the Android build and tests** run only in CI. Push the branch, open the pull request, and read its checks (`Build Cindy iOS`, `Test Cindy iOS`, `Test Cindy`) with `gh api repos/alexxgalea/cindy-workout/commits/<sha>/check-runs`.
- **Opening a pull request:** `gh pr` is blocked here (it uses GraphQL). Use `gh api repos/alexxgalea/cindy-workout/pulls -f title=… -f head=<branch> -f base=main -f body=…`, or the Create PR button on claude.ai.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->
