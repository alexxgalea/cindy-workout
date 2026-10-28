# Cindy becomes one workout among several

On 2026-10-19 the owner decided the app is a catalog of workouts rather than a Cindy counter: a workout is a named plan (movements, structure, time cap, scoring), Cindy is the first one, and Freestyle (any movement, any order, totals per movement) is the second. The reason is practical: some days the athlete does not want the whole of Cindy and still wants to train, and the same three movements already make other benchmarks possible (Chelsea as an EMOM, Angie for time). The app keeps the name Cindy, every session recorded so far becomes a Cindy session, and records, levels and badges stay per workout so a partial day never moves a Cindy record.

## Considered Options

- Cindy à la carte (rounds, but of a chosen subset of movements): rejected in favour of Freestyle, which needs no rounds and is what exercise recognition makes possible.
- Keep the app Cindy-only: rejected for the reason above.

## Consequences

- The workout is chosen on a Workouts page shown at first launch and when an update brings a workout the athlete has not seen, and afterwards from a Workout row on the MENU page; the camera HUD stays for controls used mid-set.
- The data model knows four structures (AMRAP, EMOM, For time, Free) from the start, though only Cindy and Freestyle are built first.
- Variations stay per movement and apply in every workout.
