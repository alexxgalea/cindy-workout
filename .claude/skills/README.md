# Skills in this repository

Third-party skills, copied verbatim from three MIT-licensed repositories at the commits below, so
that every Claude Code session on this repository, cloud sessions included, has them without
installing anything. Each folder keeps its upstream files; the licences are those repositories'.

| From | Commit | Skills |
|---|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | `bb92a77` | brainstorming, dispatching-parallel-agents, executing-plans, finishing-a-development-branch, receiving-code-review, requesting-code-review, subagent-driven-development, systematic-debugging, test-driven-development, using-git-worktrees, using-superpowers, verification-before-completion, writing-plans, writing-skills |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `49dd158` | codebase-design, diagnosing-bugs, domain-modeling, grill-me, grilling, handoff, implement-spec, improve-codebase-architecture, setup-matt-pocock-skills, tdd, to-spec, to-tickets, triage |
| [tirth8205/code-review-graph](https://github.com/tirth8205/code-review-graph) | `6b12d11` | build-graph, debug-issue, explore-codebase, refactor-safely, review-changes, review-delta, review-pr |

## What differs from upstream

- `using-superpowers` has `disable-model-invocation: true`. Upstream it is loaded into every
  session by a SessionStart hook and makes the agent invoke a skill before anything else. Here the
  hook is not installed and the skill runs only when asked for (`/using-superpowers`); the other
  skills are used when they fit or when asked for.
- Superpowers skills refer to each other as `superpowers:<name>`. Installed as project skills they
  are plain `<name>`: `superpowers:writing-plans` is the `writing-plans` skill.
- Matt Pocock's `code-review` is not copied, because Claude Code has a built-in `code-review`;
  `tdd` and `implement-spec` reach that one. His issue-tracker skills (`to-spec`, `to-tickets`,
  `implement-spec`, `triage`) need `/setup-matt-pocock-skills` run once first.
- Left out on purpose: Matt Pocock's TypeScript, course and in-progress skills, and Superpowers'
  `diagnosing-superpowers`.

## The graph

`.mcp.json` runs the code-review-graph MCP server (`uvx`, version pinned), and
`.claude/hooks/session-start.sh` builds the graph in a cloud session (about ten seconds). A
`PostToolUse` hook in `.claude/settings.json` updates it incrementally after edits. The database
is `.code-review-graph/`, ignored by git. Change the pinned version in all three files together.

Superpowers' visual brainstorming companion can show a logo loaded from its author's site;
`SUPERPOWERS_DISABLE_TELEMETRY=1` in `.claude/settings.json` turns that off.

## Precedence

This repository's own rules come first: `ios/PLAN.md` for the iOS port (commit style, branch
names, no attribution trailers, the plan → execute → test → review loop) and the README for
Android. Where a skill says otherwise (a `feat:` commit prefix, a branch naming scheme, opening a
PR on its own), the repository's rule wins.
