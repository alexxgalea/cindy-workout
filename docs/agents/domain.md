# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`docs/GLOSSARY.md`**: the domain's words.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context: one glossary and one set of decisions for the Android app, the iPhone app and the engine they share.

```
/
├── docs/
│   ├── GLOSSARY.md
│   └── adr/
│       ├── 0001-coach-not-referee.md
│       ├── 0002-stay-on-17-keypoints.md
│       └── …
├── app/                ← the Android app
└── ios/                ← the iPhone app and CindyCore
```

Only `docs/GLOSSARY.md`, `docs/adr/` and `docs/agents/` are in git. Everything else in `docs/` is the owner's local notes: don't link to it from tracked files.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `docs/GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
