# Navigation pages close from a top bar and the back gesture, not from a DONE pill

On 2026-11-07 the owner decided, after the prototype of icons, navigation and type, that the menu, Progress, You, Help and the session page close from a top bar and from the system back gesture, and that the full-width DONE pill goes from them. The bar holds a Back control (not a ×) and the page's title, centred. The spec behind it (#139) found that every page ended on the same white pill, including Progress and the session page, which are long and dense, so a button at the bottom did not mean an action. This amends ADR 0003's "the menu and the session page are full-screen, closed by DONE", and the iPhone port follows it.

## Considered Options

- Keep the DONE pill: rejected by the owner's verdict.
- A close control (×) at the top: rejected by the owner, who chose a Back control. The pages are pushed one inside another, and a back control says that.
- Rely on the back gesture alone: not chosen, because it is not visible, so a page with no control looks like it has no way out.
- A Back control in a top bar, with the gesture doing the same: chosen.

## Consequences

- `TopBar` is a part of the shared component library. A page places it above its content, and the control and the gesture take the same path (the activity's back dispatcher), so a page cannot close one way and not the other.
- A bottom action bar remains only where there is a real action: a sheet's SAVE and CANCEL, the session page's DISCARD, the stop question's END and KEEP GOING. Help keeps CROSSFIT.COM, which leaves the app, and the session page straight after a workout keeps PROGRESS.
- Sheets are not pages. A sheet with one choice still closes on its own button, as it did.
- The Back control is 48 dp and is named "Back" for TalkBack; the title is a heading.
- Movements was a sheet closed by SAVE and CANCEL and is now a pushed page with a top bar. A tap on a variation is saved at once, so it has no bottom bar of its own: SAVE and CANCEL were the only reason it was a sheet.
- The first-run tutorial keeps its own last step (`LET'S GO`, or `DONE` on a replay), which ends a tour, not a page.
- The iPhone app keeps DONE until its port of this change (tracked with the iPhone port of the polished interface), and ADR 0003 says so.
