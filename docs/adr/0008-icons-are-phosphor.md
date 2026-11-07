# Icons are Phosphor

On 2026-11-07 the owner chose Phosphor (MIT) as the icon set of the Android app, after comparing it with Lucide (ISC) and Tabler (MIT) on the app's own screens in the prototype `prototype/icons-navigation-type` (issue #141). The old icons, drawn by hand on a 24 unit grid at a stroke of 1.9 to 2.3, were not close enough to Apple's look, and SF Symbols is licensed only for Apple platforms. Every icon is now Phosphor's regular weight on Phosphor's 256 unit grid, shown at 24 dp, so the whole app has one weight and one grid. The iPhone app takes the same set (ADR 0003: Android is the reference, and iOS copies its icons).

## Considered Options

- Keep the hand-drawn icons: rejected by the owner; they were drawn at several stroke weights, and the verdict replaces them everywhere.
- Lucide (ISC) and Tabler (MIT): rejected by the owner in the prototype. No written reasons were given, so none are recorded here.
- SF Symbols: excluded before the comparison, because its licence covers Apple platforms only, and both apps keep one look.
- Phosphor: chosen.

## Consequences

- **One drawable per role, on one grid.** The `ic_` drawables keep their names and their places; their paths are Phosphor's. `IconSetTest` holds every `ic_` drawable to the 256 grid, to a stroke of 16 where it is stroked, and to being used by a screen, so a glyph from another set, or an old one left behind, fails the build.
- **Filled glyphs where the role is a state or a control that acts**: play, pause, stop, skip, the streak flame and the reached disc are Phosphor's fill weight; the rest are regular.
- **`ic_dont_move` is the app's own mark.** Phosphor has no "hold still" glyph (`person-simple` is a figure, not a target with ticks), so the mark stays and is redrawn on the 256 grid at Phosphor's regular weight, with round caps. It is the only icon in the app that is not Phosphor's.
- **The reached disc has its check cut out of it**, as Phosphor draws `check-circle` in fill, where the old one drew a dark check over the green; the card behind shows through.
- **Music and voice icons are gone.** Nothing used them since both settings moved to the menu; Phosphor's `music-notes` and `speaker-high` are not carried in.
- **The licence travels with the app.** The MIT notice ships as `licences/mit-phosphor.txt`, Help credits Phosphor beside the other licences, and `LicencesTest` holds the credit and the shipped text to each other.
- **The iPhone port is owed.** CindyTracker still draws its own icons; it takes these glyphs, from the same Phosphor files, in its own ticket under ADR 0003, and its licences folder gains the same MIT notice then.
