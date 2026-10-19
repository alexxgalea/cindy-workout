# The iPhone app's interface follows the Android app's

On 2026-10-19 the owner found the two interfaces "totally different" and decided the iPhone app takes the Android app's shape: the same layout, design tokens (black, the white label ramp, green only for the affirmative, Manrope with tabular figures, the glass recipe), words, icons and section order, judged by screenshots side by side rather than pixel identity. Android is the reference; when they differ iOS changes, and Android is touched only for a bug the port exposes. This reverses the P6 port's choice to render Android's custom sheet as native iOS chrome.

## Considered Options

- Native iOS chrome (`.alert`, `confirmationDialog`, `Form` sheets with Save and Cancel, Menu and the session page as swipe-down cards), as P6 shipped it: rejected, because it made the iPhone app read as a different product, and because the Android design was built and approved artboard by artboard while the iOS screens before P14 never adopted it.
- A new shared design that both apps move to: rejected, because the Android design is the settled one and only iOS is behind.
- Follow Android: chosen.

## Consequences

- In-app questions (stop, skip the setup check, discard) and the menu's choice sheets use the Cindy sheet, not system alerts. What belongs to the system stays native: the photo and file pickers, permission prompts, the share sheet, swipe-back and swipe-down gestures.
- The menu and the session page are full-screen, closed by DONE as on Android, with push navigation inside the menu.
- The camera screen has a SKIP button; skipping is no longer a long press on +1.
- The status bar and home indicator are hidden on the camera screen.
- The App Store submission waits until at least the camera screen and the session page match.
