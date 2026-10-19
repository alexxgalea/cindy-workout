#!/bin/bash
# Prepares a Claude Code cloud session: turns on the repository's git hooks, and builds the
# code-review-graph knowledge graph of this repository, so its MCP server (.mcp.json) and its
# skills have a graph to answer from.
#
# The container is fresh each time, so the graph is rebuilt here: about ten seconds for the whole
# repository (Kotlin, Swift, Python, shell). The version is pinned, here and in .mcp.json and
# .claude/settings.json; change all three together. It never fails the session: without uvx, or
# if the build fails, it says so and the session starts without a graph.
set -uo pipefail

# Drain the hook's JSON input.
cat >/dev/null || true

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

CRG="code-review-graph==2.3.9"
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

# The history carries no attribution trailers. `attribution` in .claude/settings.json stops them
# being written; the commit-msg hook takes out any that get through another way.
git config core.hooksPath .githooks

if ! command -v uvx >/dev/null 2>&1; then
  echo "[code-review-graph] uvx is not installed, so there is no graph this session."
  exit 0
fi

if uvx --from "$CRG" code-review-graph build >/dev/null 2>&1; then
  # Prints the node, edge and file counts, so the session knows the graph is there.
  uvx --from "$CRG" code-review-graph status 2>/dev/null | sed 's/^/[code-review-graph] /'
  echo "[code-review-graph] Prefer its MCP tools (semantic_search_nodes_tool, query_graph_tool," \
    "get_impact_radius_tool, detect_changes_tool) before scanning files; read the source before changing it."
else
  echo "[code-review-graph] The graph build failed; run 'uvx --from $CRG code-review-graph build' to see why."
fi
exit 0
