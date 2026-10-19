# App Privacy answers

App Store Connect → App Privacy, for each of the two builds. Which to enter depends on whether the
build was made with `ios/Config/Strava.xcconfig` (ios/README.md, Strava). Each answer says which code
makes it true. If that code changes, this changes with it, and so do the privacy manifests
(`ios/CindyTracker/PrivacyInfo.xcprivacy`, `ios/Config/PrivacyInfo.strava.xcprivacy`), the policy,
Help's PRIVACY section and the Strava consent sheet.

## Confirm before you submit

Three answers are judgement calls that Apple's wording does not settle. Read the form's help text for
each before you press publish.

1. **Strava is *collected*.** Apple's definition is data transmitted off the device so that it can be
   accessed for longer than the request needs. Strava keeps the workout, so it counts, although it goes
   only where the athlete sent it, on a tap on Strava's own button, to their own account. Apple's
   questions about third-party partners are about SDKs and services the developer chose to run;
   this is the athlete's own account, but the conservative reading is to declare it.
2. **It is declared as linked to the athlete's identity.** The upload goes to a Strava account, which
   is the athlete's identity there. Cindy never reads who that is, but the data is linked. The
   manifest says the same (`NSPrivacyCollectedDataTypeLinked` true), and `StoreMetadataTests` holds
   the two together.
3. **No identifier is declared for Strava.** The access token identifies the account but is a credential
   rather than a data type in Apple's list. Add *Identifiers → User ID* (linked, app functionality) if
   you would rather be conservative.

## Build without Strava

**Data Not Collected.** Everything is processed on the iPhone. The only network use in the app is Strava,
and without credentials `StravaConfig.available` is false and nothing reaches for the network. The
camera picture is analysed on the device and discarded. Heart rate comes over Bluetooth and stays.
Videos are saved to Photos by the athlete's own tap, add-only.

Tracking: **No**. The app has no `NSUserTrackingUsageDescription`, no advertising identifier and no
third-party code.

## Build with Strava

Declare these, and nothing else:

| Data type | Collected | Linked to the athlete | Used to track | Purpose |
|---|---|---|---|---|
| Health & Fitness → **Fitness** (the workout: its sets, reps, duration and calories) | Yes | Yes | No | App Functionality |
| Health & Fitness → **Health** (heart rate, only if a monitor was worn) | Yes | Yes | No | App Functionality |

Both are optional, in the sense that nothing is sent until the athlete connects Strava, and then only
for sessions that finish. Tracking: **No**. Not declared: Photos (add-only, never read), Contacts,
Location, Usage Data, Diagnostics, Identifiers.

## The privacy policy address

`https://alexxgalea.github.io/cindy-privacy/ios/`, rendered for the same build with
`tools/play/render.py --store appstore` (README). The manifests, the labels and the policy must all
describe the same build; the policy for a build without Strava does not mention Strava anywhere, and a
test holds it to that.

## Privacy manifest, for reference

Required-reason APIs used, the audit being `StoreMetadataTests.testTheManifestNamesEveryRequiredReasonApiTheCodeUsesAndNoneItDoesNot`:

| Category | Reason | Why |
|---|---|---|
| UserDefaults | CA92.1 | the app's own settings and records, read only by the app |
| SystemBootTime | 35F9.1 | measuring time elapsed inside the app (the workout clock); the uptime is never sent or stored |

File timestamps, disk space and active keyboards are not used.
