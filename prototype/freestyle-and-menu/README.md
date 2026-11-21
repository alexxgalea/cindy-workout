# Prototype: the MENU page and Freestyle

Throwaway. Lives on `prototype/freestyle-and-menu`, out of `main`, never merged. The decisions it starts from are in the 2026-11-21 grilling: the glossary's Freestyle, Figure, Set, Rest, Transition entries and ADR 0010.

**Open it:** double-click `index.html`, or `open prototype/freestyle-and-menu/index.html`. No server, no build, no network.

Switch the page at the top, the variant with the yellow bar or ← →. The URL keeps both (`?page=menu|camera|session&v=A|B|C`). Every page prints its state beside the phone.

| Page | Variants |
|---|---|
| MENU | A grouped sections (Training, You, Settings) · B a "next session" block, then the last session with its figures, then settings with icons · C today's list, reordered only |
| Freestyle camera | A confirmation is a pulse · B confirmation is a 1.5 s takeover with the movement's name |
| Freestyle session page | A totals, then the sets in order with rests and transitions · B a strip across the session's time · C one card per movement, its sets as chips |

The camera page plays a scripted Freestyle (squats, a 22 s rest, squats, a walk, pull-ups, push-ups, a 9 s gap, push-ups) and logs what the voice would say. `?steps=N` plays the first N reps at once, and `&paused=1` then pauses it, for a still.

**Open question it exposes:** the figure is "this set", but sets are worked out after STOP, so the screen needs its own rule for when the figure goes back to 1. The switch on the camera page compares "only on a new movement" against "also after a gap".

What is not real: the phones are HTML recreations in dp, the picture is a drawn stick figure, icons named `x-…` in `icons.js` are hand-drawn stand-ins (the rest are Phosphor), and the session's numbers are invented. No blur.

## Verdict (owner, 2026-11-21)

A on every page:

- **MENU: A**, grouped sections. Last session alone at the top, then Training (Workout, Movements, Progress), You, Settings, Help.
- **Freestyle camera: A**, confirmation is the pulse every banked rep has; no takeover.
- **Freestyle session page: A**, totals per movement and the time, Cindy's tiles, then every set in order with its rest or transition.
- **The figure goes back to 1 only on a new movement.** A rest inside one movement does not reset it, so the screen may show 16 where the session page later shows sets of 12 and 4.
