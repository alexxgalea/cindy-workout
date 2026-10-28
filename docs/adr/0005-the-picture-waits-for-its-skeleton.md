# The picture runs behind the athlete on purpose, so the skeleton never lags it

On 2026-10-27 the owner chose to hold every frame of the picture until the skeleton computed from that very frame is ready, and to show the two together, in every build and with no setting. Before this the picture was live and the skeleton, drawn over it, trailed the body: worst at the top of a pull-up and through fast squats. The price is picture delay, raised on purpose. A later reader who sees a picture held back by about 130 ms should not "fix" it: the alternatives below were measured or refuted, and each leaves skeleton lag or costs something worse.

The decision was taken on a Huawei P40 over one round of push-ups and squats per mode, read from the latency readout on a cool phone (model 40 ms, 22 analysed frames a second):

| | live picture | synced, analysed frames only | synced, every frame (chosen) |
|---|---|---|---|
| How far the skeleton is behind the athlete | 111–128 ms (median 119) | 110–127 (117) | 110–125 (116) |
| Picture delay | not measured | 111–128 ms (118) | 128–142 ms (133) |
| Picture updates a second | ~40 (picture and skeleton redraw apart) | 22.4, longest gap 94 ms | 29.9, longest gap 102 ms |
| Frames shown without their skeleton | n/a | 0 | 0 |

On one squat rep seen frame by frame (10 frames, 100 ms apart) the live skeleton detaches from the body on the way down and up; in both synced modes it sits on the body in all 10.

The P40's skeleton is not always that young. The earlier probe measured it at about 150–195 ms behind the athlete, depending on the scene, with model time rising from 33 ms cool to 60 ms warm and analysis falling from about 18 to about 14.5 frames a second. Treat 150–195 ms as the planning range for the skeleton, and the picture delay as that plus the wait for the next skeleton. The September figures, from a Reno5 5G that is no longer available, were a skeleton about 148 ms behind the athlete (about 94 ms camera and image processing, about 10 ms preparing the input, about 44 ms the model) at about 17 frames a second, against a picture about 90 ms behind.

## Considered Options

- **A faster model (MoveNet Lightning)**: saves about 23 ms on the Reno5, costs accuracy on overhead wrists. The best case, about 125 ms, still trails visibly. Most of the skeleton's age is camera and image processing (about 94 ms on the Reno5, 83–130 ms on the P40), which nothing in the app reaches.
- **Motion prediction** (drawing each joint ahead along its recent velocity, bounded): refuted twice. It cannot cover 150 ms on a stream of about 17 frames a second, of a movement that reverses every half second, and where it fails it draws a joint where the body never was, at the top of a pull-up. It is deleted on Android; the iOS copy waits for the iOS port.
- **The live picture with the skeleton drawn over it**, as before: no picture delay, and skeleton lag by construction. It stays only as a diagnostic, in the debug readout.
- **Synced, analysed frames only**: the same wait, but the picture shows only the frames the model saw, so its rate is the analysis rate and moves with the phone's heat: 22.4 a second cool on 2026-10-27, 11.7 a second with gaps of about 86 ms warm on 2026-10-26.
- **Synced, every frame**: chosen. It held 29.4–29.9 updates a second on both days for about 15 ms more picture delay than analysed frames only (133 against 118 ms), and the film is always every frame, so the screen and the film behave alike.

## Consequences

- The picture runs about 130–140 ms behind the athlete on a cool P40, and further behind on a warm one. A frame waits at most 250 ms for its skeleton and is then shown without one, never with an old one, so the picture never freezes. If the readout's timed-out count rises on a warm round, revisit the 250 ms cap, not the choice.
- The picture is synced during the setup check as well, and in release builds as in debug. A phone whose camera cannot bind the synced picture falls back through a plain film, then no film, then the live picture with counting only, and there the skeleton lags again. Counting never depends on either effect.
- Not checked when this was decided: pull-ups, including the top of a pull-up; the setup check; the every-frame picture on a warm phone; a film made by the app.
- The iPhone app is untouched: its copy of motion prediction stays until the iOS port of this work.
