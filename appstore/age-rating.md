# Age rating and the rest of App Store Connect

The answers to the forms that are not the listing or the privacy labels, in the order App Store
Connect asks. Where a build with Strava differs, it says so.

## Age rating

Answer **None** (or No) to every content question: violence, sexual content and nudity, profanity,
horror, alcohol, tobacco and drugs, gambling, contests. The app has no user-generated content, no
messaging, no web browsing inside the app (Help and the policy open in Safari), no loot boxes and no
purchases. The exercises are shown as a stick figure.

Two questions are worth reading in the form itself:

- **Medical or wellness topics.** The app is a rep counter, not a medical product; Help and the listing
  both say heart rate, zones and calories are training estimates. Answer by the form's own wording,
  and expect **4+**. If the answer would raise the rating, it is the only reason.
- **Social features / sharing.** With Strava, the athlete's workout appears on their own Strava
  account, which is Strava's feature, not an interaction inside Cindy. Answer No.

Apple derives the rating from the answers, so check the number it shows is 4+ before you accept it.

## App information

| Field | Value |
|---|---|
| Name | `Cindy Tracker: Rep Counter` (`listing/en-US/name.txt`) |
| Primary category | Health & Fitness (secondary: Sports) |
| Content rights | Does not contain, show or access third-party content |
| Privacy policy URL | `https://alexxgalea.github.io/cindy-privacy/ios/` |
| Support URL | the repository's issue page, or an address of your own |
| Copyright | the year and your name |
| Price | Free, no in-app purchases |
| Encryption | Already answered by the build: `ITSAppUsesNonExemptEncryption` is false, because the only encryption is HTTPS to Strava (CryptoKit is not used) |
| Advertising identifier | Not used |

## App Review Information

Contact name, email and phone are yours. **Sign-in required: No.** Paste `review-notes.txt` (render it
with the build you uploaded: the Strava paragraph is only in the build with Strava).

The app asks for the camera when the first workout starts, Bluetooth when a heart-rate monitor is
connected, and Photos (add-only) when a recording is saved. Each purpose string says what it is for;
none is needed to review the rest.

## Version information

Promotional text, description, keywords and What's New come from `listing/en-US/`. Screenshots are
yours (appstore/README.md). There is no demo video requirement.
