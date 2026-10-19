# Stay on 17 keypoints: MoveNet on Android, Vision on iOS

New intelligence (rep quality, trends, unbanked attempts) is built on the 17 COCO keypoints the app already has, not on MediaPipe Pose Landmarker's 33 landmarks. Decided on 2026-10-19: Android runs MoveNet (uint8, tuned crop and low-light lift), iOS maps Apple Vision onto the same 17 points, and the Kotlin, Python and Swift engines are held to one frame-by-frame parity trace on those points. Switching models would mean re-tuning Android, rewriting parity across three engines, and either replacing Vision on iOS or running two models. We switch only if a specific feature is shown to need landmarks we lack (feet, hands, depth).

## Considered Options

- MediaPipe Pose Landmarker (33 landmarks, world coordinates): better feet and hands for squat analysis, but the cost above for every platform.
- A higher-accuracy offline model (MoveNet Thunder or RTMPose) for saved clips only: not needed until clips of weak reps exist.
