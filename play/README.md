# Google Play: listing, policy and answers

Everything Google Play asks for that is not the app itself. It is kept here, next to the code,
because it has to agree with the code: a Data safety answer or a policy sentence that says something
the app does not do is the kind of mismatch Play's review looks for.

```
play/
├── listing/en-US/        title, short description and full description (plain text)
├── privacy-policy.html   the policy page, as a template
├── data-safety.md        the Data safety form, answer by answer  (added with the answers)
├── console-answers.md    the rest of Play Console's questionnaires (added with the answers)
├── graphics/             the 512 px icon and the 1024 x 500 feature graphic (added with the art)
└── dist/                 what the renderer writes; gitignored
```

## Two builds, one source

Whether the app has Strava is decided by whether `strava.properties` exists when the bundle is
built (see the README's Release section). Play's listing, the policy and the Data safety answers
all differ between the two, so the text is written once with two kinds of block:

- `{{#strava}} … {{/strava}}` is kept for a build with Strava and dropped for one without;
- `{{^strava}} … {{/strava}}` is the other way round.

Blocks do not nest. The policy also has three details only its publisher knows, written as
`{{DEVELOPER_NAME}}`, `{{CONTACT_EMAIL}}` and `{{EFFECTIVE_DATE}}`. They are never committed filled
in.

## Rendering

```sh
python3 tools/play/render.py --strava    --name "Your Name" --email you@example.com
python3 tools/play/render.py --no-strava --name "Your Name" --email you@example.com
```

This writes `play/dist/privacy-policy.html`, the page to publish at the address the app opens
(`AppLinks.PRIVACY_POLICY`), and `play/dist/listing/`, to paste into Play Console. The name must be
the developer name exactly as it appears on the store listing, because Play checks the two match.
The script refuses to write anything while a placeholder or marker is left over, or if the build
without Strava mentions Strava anywhere. `python3 tools/play/render.py --check` renders both builds
with stand-in values and is what CI runs.

## What keeps it honest

- `PlayListingTest` holds the listing to Play's length limits and metadata rules, and to the
  number of voice languages the app really has.
- `PlayPolicyTest` holds the policy to what Play requires of one, to the consent sheet's list of
  what an upload sends, and to Help's PRIVACY section.
- A change to what the app stores or sends changes the policy, the Data safety answers, Help's
  PRIVACY section and the Strava consent sheet together, or none of them.
