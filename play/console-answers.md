# Play Console answers

The rest of Play Console's questionnaires, in the order the console asks them, with the answer to
give and the reason. The Data safety form has its own file, [data-safety.md](data-safety.md). Where
an answer differs between a bundle built with Strava and one without, both are given.

## Before the first upload

| Step | What to do |
|---|---|
| Developer account | Personal accounts created after 2023-11-13 must run a closed test with at least 12 testers, opted in for 14 days in a row, before they can apply for production. Start recruiting now. |
| Create the app | Name `Cindy Tracker: Rep Counter` (26 of 30 characters), default language English (United States), App, Free. |
| Package name | `com.cindy.tracker`. It is permanent from the first upload. |
| Play App Signing | Accept it. The upload key is yours (see the README's Release section); Google holds the signing key. |

## App content

**Privacy policy.** `https://alexxgalea.github.io/cindy-privacy/`. Publish the page rendered by
`tools/play/render.py` there first, and open it logged out to check it is not behind a login and is
not a PDF. The developer name on the page must match the one on the store listing.

**Ads.** No, the app contains no ads.

**App access.** *All or some functionality is restricted* is the wrong answer: nothing needs a sign-in.
Choose *All functionality is available without special access*, and add these instructions for the
reviewer, which are true of the app:

> There is no sign-in. The app counts exercise repetitions from the camera, so the camera screen
> expects a person in frame. To step through a workout without one, tap START, then SKIP on the
> setup check, and use +1 to book reps by hand. The menu button on the camera screen opens Help,
> Progress and the other screens.

*With Strava:* add "Strava upload needs the reviewer's own Strava account; every other feature
works without one." A new Strava application only lets its owner connect until it is raised to 10
athletes, so a reviewer can only complete that step once Strava has done so. Leave the Strava step
out of the instructions until then.

**Target audience and content.** 18 and over. Not designed for children, and does not appeal to them
(no cartoon characters, no games). This keeps the app out of the Families policy.

**Content rating.** Category: *Utility, Productivity, Communication, or Other*. Answer *No* to
violence, sexual content, language, controlled substances, gambling and user-generated content, and
*No* to sharing the user's location or letting users interact. The app has no purchases. This should
come out at the lowest rating (Everyone / PEGI 3 / USK 0), but the questionnaire decides.
*With Strava:* the athlete's workout appears on their own Strava account, which is Strava's feature,
not an interaction inside Cindy. Answer the interaction question *No*, and re-read it when you reach
it.

**News app.** No. **COVID-19 contact tracing or status.** No. **Government app.** No.
**Financial features.** None.

**Advertising ID.** The app does not use it. The merged release manifest contains no
`com.google.android.gms.permission.AD_ID`, which was checked on the release build.

**Health apps declaration.** Required of every app. Choose *Health and fitness → Activity and
fitness tracking*. It is not a medical device, does not diagnose, and does not use Health Connect.
Help and the listing both say heart rate, zones and calories are training estimates.

**Data safety.** See [data-safety.md](data-safety.md).

## Permissions, if Play asks

None needs a special declaration form, which is for background location, SMS, call log and the like.
If a review asks why the app holds one:

| Permission | Why |
|---|---|
| `CAMERA` | The whole point of the app: it reads the pose from the camera. Declared `required`. |
| `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT` | Finding and reading a heart-rate watch or strap. |
| `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` | Only up to Android 11 (`maxSdkVersion` 30), where Android ties a Bluetooth scan to the location permission. The app never reads a location, and Android 12 and newer never ask. Explained to the athlete before the prompt. |
| `POST_NOTIFICATIONS` | The daily reminder, which is off until the athlete turns it on. |
| `RECEIVE_BOOT_COMPLETED` | Re-arming that reminder after a restart. |
| `VIBRATE` | The buzz at each rep and round. |
| `WRITE_EXTERNAL_STORAGE` | Only up to Android 9 (`maxSdkVersion` 28), to save a recording to Movies/Cindy. |
| `INTERNET` | Strava, and nothing else. In a bundle built without Strava nothing uses it. |

WorkManager's manifest adds `FOREGROUND_SERVICE`, `WAKE_LOCK` and `ACCESS_NETWORK_STATE`. The app
never starts a foreground service, so Play's foreground-service declaration does not apply.

## Store presence

**Category.** Health & Fitness. **Tags.** Up to five that describe the app: fitness tracker,
workout, exercise, rep counter.
**Contact details.** The email on the policy. A website is optional; the policy page will do.
**Listing text.** Rendered into `play/dist/listing/` by `tools/play/render.py`; paste it in.
**Graphics.** `play/graphics/`: the 512 px icon and the 1024 x 500 feature graphic.

**Screenshots.** Take them on the phone, with a demo profile, no real name or photo. At least four,
portrait, 1080 x 1920 or larger:

1. The camera screen mid-workout, with the skeleton and the counter.
2. The framing check, or the placement guide.
3. The results page: the tiles and the round track.
4. The timeline, with the heart-rate lane.
5. Progress: the chart and the calendar.
6. The badges.

With Strava, add the consent sheet. Strava's own review wants it, "View on Strava" on a finished
upload, and the connected sheet, and they are good screenshots for the listing too if you want to
mention Strava in it.

## Releasing

1. Build the signed bundle (README, Release), and check it: the 16 KB script and `keytool -printcert`.
2. Internal testing first: upload, install from Play, and run a whole workout, a recording and a
   heart-rate pairing, and, with Strava, a connect and an upload.
3. Closed testing next, for the 14 days and 12 testers above. Read the pre-launch report: the robot
   cannot do a workout, so noise on the camera screen is expected and a crash is not.
4. Apply for production from the dashboard, then roll out in stages, watching Android vitals.

Every upload needs a higher `versionCode` than the last.
