# Data safety form

The answers to Play Console → App content → Data safety, for each of the two builds. Which one to
submit depends on whether the bundle was built with a `strava.properties` (see the README's Release
section): a bundle without it has no Strava at all, so it **collects nothing**.

Each answer says which code makes it true. If any of that code changes, this changes with it, and so
do the privacy policy, Help's PRIVACY section and the Strava consent sheet.

## Confirm before you submit

Three answers are judgement calls Google's own wording does not settle. They are the ones to read
the form's help text for, in the form itself, before you press submit.

1. **Android's backup is not declared.** Google defines *collection* as transmitting data off the
   device. Auto Backup copies the app's preferences and files to the athlete's own Google account,
   but it is Android that does it, not the app's code, and the athlete controls it. I found no
   sentence from Google that names backup either way, so this follows the definition. If the form
   or its help text says backed-up data counts, the build without Strava would have to declare
   the personal and health data in `backup_rules.xml` and `data_extraction_rules.xml`.
2. **Strava is *collected* but not *shared*.** Sending a workout to Strava is data leaving the
   device, so it is collected. Google's list of what is not *sharing* includes "transferring user
   data to a third party based on a specific user-initiated action, where the user reasonably
   expects the data to be shared", and the Strava consent sheet is the prominent disclosure and
   the tap on Strava's own button is the action. That is the basis for answering "not shared".
3. **No user ID is declared for Strava.** The app sends Strava an access token that identifies the
   connected account. Cindy neither chooses nor reads an identifier, and the token is a credential
   rather than a data type in the form's list. If you would rather be conservative, add *Personal
   info → User IDs* as collected, optional, for app functionality.

## Build without Strava

**Does your app collect or share any of the required user data types?** No.

Everything is processed on the device. The app's only network use is Strava (`INTERNET` is there for
nothing else), and this build has no Strava: with no credentials `StravaConfig.available` is false
and nothing in the app reaches for the network.

Nothing else on the form is asked once that answer is no. The privacy policy address is entered
separately, under App content → Privacy policy: `https://alexxgalea.github.io/cindy-privacy/`.

## Build with Strava

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes. Every request goes to
`https://www.strava.com` (`StravaConfig.API_BASE` and `OAUTH_BASE`).
**Which methods of account creation does your app support?** None. There is no account.
**Do you provide a way for users to request that their data is deleted?** No. Cindy keeps nothing on
a server; the copy at Strava is the athlete's own and is removed on Strava. The local data is
deleted in the app (CLEAR, REMOVE) and the connection is ended with DISCONNECT, all of which the
policy and Help describe. Google does not require this answer for every app: the badge is for
apps that offer a deletion mechanism.

| Data type | Collected | Shared | Ephemeral | Required or optional | Purpose |
|---|---|---|---|---|---|
| Health and fitness → **Health info** (the heart-rate trace, when a watch recorded one) | Yes | No | No | Optional | App functionality |
| Health and fitness → **Fitness info** (the sets and reps, times, and the calorie estimate) | Yes | No | No | Optional | App functionality |

*Optional* because Google's definition is a type "where a user has control over its collection and
can use the app without providing it", and the athlete can use Cindy without connecting Strava, or
with automatic upload switched off.

What is sent is exactly `StravaPayload.json` and `StravaActivityText`: the score, each set with its
movement and reps, the start time and its offset from UTC, the clock, paused and real time, the
calorie total when a body weight is set, the heart-rate stream when a watch recorded one, and a
title and description. It does not include body weight, birth year, sex, name, photo, video or pose.

**Not declared, and why:**

- *Name.* Strava sends the athlete's name to the app to say who is connected. It is received, not
  transmitted from the device.
- *Approximate location.* The upload carries the time-zone offset, not a location. The app does not
  request location on Android 12 and newer, and never reads it on older versions.
- *Device or other IDs, advertising ID.* None are read, and the merged manifest has no
  `com.google.android.gms.permission.AD_ID`.
- *App activity, app info and performance, financial info, messages, photos and videos, audio
  files, files and docs, calendar, contacts.* Nothing is collected in these. The photo the athlete
  picks for their profile, the video they record, and the music track they choose stay on the phone.

## Security practices, either build

| Question | Answer |
|---|---|
| Data is encrypted in transit | Yes in the build with Strava; not asked in the build without |
| You can request that data be deleted | No (see above) |
| Committed to follow the Play Families Policy | No: the audience is adults |
| Independent security review | No |
