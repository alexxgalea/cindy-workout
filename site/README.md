# The landing page

The page behind the Instagram link. Plain HTML, no build step: `index.html`, `config.js`, `img/`
and `fonts/` are published as they are, to the user-site repository `alexxgalea.github.io`.

Open `index.html` through any static server (`python3 -m http.server --directory site`); `?lang=ro`
and `?lang=en` pick the language.

## When the app is on Google Play

Set `mode: "play"` in `config.js`. The "join the testers" steps give way to one "Get it on Google
Play" button, and the line under the title changes to match. Nothing else needs editing.

## While the closed test runs

`groupUrl` is the Google Group the closed track allows. Until it is set the page still renders, but
`python3 tools/site/check.py --deploy` refuses it, so the deploy cannot go out with a dead button.

`python3 tools/site/check.py` runs in CI: it holds the config, the two languages (same keys) and
the files the page points at.

The screenshots are copies of `play/dist/screenshots/phone/` (ignored by git), shrunk to 540 px.
