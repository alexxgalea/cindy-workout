# App Store: listing, policy and answers

Everything App Store Connect asks for that is not the app itself, kept next to the code because it
has to agree with it. It is the iPhone counterpart of [play/](../play/README.md) and is written the
same way, so read that README for the idea; this one says what differs.

```
appstore/
├── listing/en-US/        name, subtitle, promotional text, description, keywords, release notes
├── review-notes.txt      what App Review is told, to paste into App Review Information
├── privacy-policy.html   the policy page for the iPhone app, as a template
├── privacy-labels.md     the App Privacy answers ("nutrition labels"), for each build
├── age-rating.md         the age rating questionnaire, and the rest of App Store Connect's forms
├── graphics/             the 1024 px icon (no alpha); screenshots are yours to take
└── dist/                 what the renderer writes; gitignored
```

## Two builds, one source

Whether the app has Strava is decided by whether `ios/Config/Strava.xcconfig` exists when it is
built (see ios/README.md, Strava). The listing, the policy and the privacy labels all differ between
the two, so the text uses the same two blocks as `play/`: `{{#strava}} … {{/strava}}` is kept for a
build with Strava, `{{^strava}} … {{/strava}}` for one without. The policy's `{{DEVELOPER_NAME}}`,
`{{CONTACT_EMAIL}}` and `{{EFFECTIVE_DATE}}` are filled in at render time and never committed.

The build itself follows the same split. `ios/CindyTracker/PrivacyInfo.xcprivacy` declares that
nothing is collected; a build with credentials has a script phase that swaps in
`ios/Config/PrivacyInfo.strava.xcprivacy`, which adds Health and Fitness. CI builds both and reads
the manifests back out of the products.

## Rendering

```sh
python3 tools/play/render.py --store appstore --strava    --name "Your Name" --email you@example.com
python3 tools/play/render.py --store appstore --no-strava --name "Your Name" --email you@example.com
```

This writes `appstore/dist/privacy-policy.html`, the page to publish at
`https://alexxgalea.github.io/cindy-privacy/ios/` (the address the app opens, `AppLinks.privacyPolicy`;
the Android page at the parent address is a different file and is left alone), and
`appstore/dist/listing/` plus `appstore/dist/review-notes.txt`, to paste into App Store Connect.
It prints each text's length against Apple's limit. `python3 tools/play/render.py --check` renders
both builds of both stores with stand-in values and is what CI runs.

## Archiving and uploading

You need the Apple Developer Program, a bundle ID registered to your team (the project says
`com.cindy.tracker`; if that is taken, change it in `ios/project.yml`, and the Strava redirect scheme
follows), and Xcode on a Mac.

1. For a build with Strava, put the credentials in `ios/Config/Strava.xcconfig` first. Leave the file out
   for one without. The two are different uploads and different App Privacy answers.
2. `cd ios && xcodegen generate && open CindyTracker.xcodeproj`.
3. Signing & Capabilities: choose your team, automatic signing.
4. Choose **Any iOS Device (arm64)**, then Product → Archive.
5. In the Organizer, Distribute App → App Store Connect → Upload. Xcode checks the privacy manifest
   and the icon here, and the build appears in App Store Connect after processing.
6. Every upload needs a build number nobody has used: raise `CURRENT_PROJECT_VERSION` in `ios/project.yml`
   (`StoreMetadataTests` reads it, so change the test's expectation with it). `MARKETING_VERSION` is the
   1.0.0 users see, and each version needs `listing/en-US/release-notes/<version>.txt`.

**TestFlight first** (decision D8). Internal testers (up to 100, members of your App Store Connect team)
need no review and get the build within minutes of it processing. External testers need a one-off Beta
App Review, which reads the same review notes. The App Store submission then adds the listing, the
screenshots, the App Privacy answers and the age rating.

## What you have to do yourself

- Join the Developer Program, register the bundle ID, sign, upload.
- Take the screenshots on a real iPhone: 6.9-inch (or 6.5-inch) is required, and App Store Connect
  scales the rest. The camera screen needs a person in frame; the results screen is easiest to reach
  with SKIP and +1 (see review-notes.txt).
- Publish the policy page, and open it logged out to check it is not behind a login and is not a PDF.
- Enter the App Privacy answers and the age rating from the two files here, and read the help text of
  the three judgement calls at the top of privacy-labels.md first.
- Add TestFlight testers.

## What keeps it honest

- `AppStoreListingTests` holds the listing to Apple's limits and metadata rules, to the number of voice
  languages the app really has, and the policy to its placeholders and its Strava blocks.
- `StoreMetadataTests` holds the privacy manifest to the APIs the source really uses (both ways), the
  version, the encryption declaration, the icon, and the policy address.
- A change to what the app stores or sends changes the policy, the labels, Help's PRIVACY section and the
  Strava consent sheet together, or none of them.
