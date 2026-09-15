# Releasing

How a build gets from this repo onto Google Play, and the things that are easy to
get wrong once and hard to undo.

## The upload key

`cindy-upload.jks` and `keystore.properties` sit at the repository root and are
**gitignored**. They are not in git and must never be.

- `keystore.properties` holds the store path, alias and both passwords.
- The key is RSA 4096, alias `cindy-upload`, valid until 2054.
- SHA-256 fingerprint: `7E:62:9D:A4:E2:54:AD:C1:93:A7:E5:0B:91:1F:0C:C2:27:49:C5:38:FF:D0:32:5B:2B:E0:F4:F6:22:39:7B:E3`

**Back both files up somewhere that is not this laptop** — a password manager is
the right home for `keystore.properties`. Losing them is recoverable but tedious:
with Play App Signing enrolled, Google holds the actual app signing key, so a lost
*upload* key can be reset through Play Console support. Without Play App Signing
it would be unrecoverable, which is one of several reasons to enrol.

A machine without `keystore.properties` still builds. `signingConfigs` only
creates the `upload` config when the file is present, and `signingConfig` resolves
to null otherwise, so the release build comes out unsigned rather than failing
with a confusing error. That is deliberate: CI and a fresh clone should be able to
compile without secrets, and an unsigned bundle fails visibly at upload.

## Building

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"

./gradlew testDebugUnitTest lintRelease bundleRelease
```

Output: `app/build/outputs/bundle/release/app-release.aab` (~15 MB). Play requires
the bundle, not an APK. Verify it is signed before uploading:

```sh
unzip -l app/build/outputs/bundle/release/app-release.aab | grep 'META-INF/.*\.RSA'
```

`assembleRelease` also produces a signed APK, which is the only way to install the
release variant directly for testing. **Do that at least once per release** — see
below for why.

### Always smoke-test the release variant on a device

Debug and release are different builds, and `BuildConfig.DEBUG` now changes real
behaviour: the pose-model swap and the latency readout are registered only in
debug. A mistake in that gating is invisible to every unit test, to lint, and to
the entire debug workflow.

This already happened once. Gating the long presses with an early `return` in
`onCreate` compiled cleanly, passed 315 unit tests, passed lint, and would have
shipped an app that launched to a dead screen with no camera, because everything
after the return — the rep controls, the engine, `startCamera()` — was skipped in
release only. It was caught by building the release variant, not by any test.

```sh
./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
```

Then actually open it, grant the camera, start a workout, count a few reps.

## Versioning

`versionCode` and `versionName` live in `app/build.gradle.kts`. **Every upload
needs a higher `versionCode`**, including a re-upload of the same code after a
rejection. Play never accepts the same number twice, even for a deleted release.

## Before the first submission

Engineering is done; these are not.

- [ ] **Privacy policy at a public URL.** Mandatory for every listing, and
      non-negotiable with `CAMERA`. Must remain reachable for the life of the app.
- [ ] **Data safety form.** This app's answers are the easy case — see below.
- [ ] **Content rating questionnaire** and target-audience declaration.
- [ ] **Store assets:** icon (512×512), feature graphic (1024×500), at least two
      phone screenshots, short and full description.
- [ ] **Enrol in Play App Signing** (default for new apps; confirm it).

### Data safety answers

Everything runs on the device. There is no server, no account and no upload, so:

| Question | Answer |
|---|---|
| Does the app collect or share user data? | **No** |
| Camera / photos and videos | Used on-device only; not collected, not transmitted |
| Health and fitness data | Stored on-device only; not collected, not transmitted |
| Is data encrypted in transit? | N/A — no data is transmitted |
| Can users request deletion? | Yes — records are cleared from the app, and uninstalling removes them |

Android Auto Backup carries records and settings to the **athlete's own** Google
Drive (see `res/xml/backup_rules.xml`). That is the user's storage, not the
developer's, and is not data collection for the purposes of this form.

### Be accurate in the listing

The app counts reps from a camera, and the counting degrades in low light in a way
that is documented and deliberate — it undercounts rather than inventing reps, and
says so. The store description should not claim precision the app declines to
claim about itself. See `OPTIMISATION.md`, Phase 2.

## Roll out through internal testing first

Do not ship straight to production.

1. Upload the AAB to the **internal testing** track.
2. Read the **pre-launch report**. Play runs the build on real devices in a lab
   and reports crashes, ANRs and accessibility issues for free. This is the
   cheapest device coverage available, and it matters here: the app has run on
   two handsets, and every measured number in `OPTIMISATION.md` comes from one of
   them.
3. Add testers by email, collect a round of feedback, then promote to closed or
   production.

The failure mode worth watching for is not a crash. It is **silent undercounting**
on a handset whose camera behaves differently — a tester will report "it felt
wrong", not a stack trace. Ask testers for the score they expected alongside the
score they got.

## Deliberately not done

- **Minification is off.** `proguard-rules.pro` is empty and TFLite reaches for
  classes reflectively; R8 would strip them with nothing failing at compile time.
  Turning it on means writing keep rules *and* re-running the on-device
  benchmarks, not flipping a flag.
- **No crash reporting SDK.** Play Console vitals is the only signal, which means
  crashes are learned about after users hit them.
- **Both pose models ship** (~10 MB of the bundle). Lightning is only reachable
  from the debug model swap, so a release build never loads it. Dropping it would
  save ~2.9 MB at the cost of the on-device A/B that settles the accuracy
  question.
