# •bullet: Accessibility Nutrition Labels in App Store Connect

These show on the App Store product page. TestFlight doesn't need them.
The answers match docs/app-store-connect.md as of 2026-09-18.

## Get there
1. App Store Connect → Apps → **•bullet** → **Distribution** tab.
2. Left sidebar → **Accessibility** (next to App Information / App Privacy).
3. **Add Device** (or **Get Started** the first time).

## Devices to add
- **iPhone**: yes
- **iPad**: yes (same app, universal)
- **Apple Watch**: yes (ships inside the iOS app)
- **Mac**: no. No Mac build has been submitted, and it hasn't been tested.

## Answers, per device (iPhone, iPad, Apple Watch)
Apple asks whether someone can finish the app's *common tasks* with each
feature. For bullet those are: add a bullet, edit it, complete it, restore it,
reorder the list, delete for good.

| Feature | Answer | Why |
|---|---|---|
| VoiceOver | **No** | Controls are labelled and Apple's audit passes, but nobody has used the app with VoiceOver yet |
| Voice Control | **No** | Not checked |
| Larger Text | **Yes** | Lora scales with Dynamic Type, and the audit's clipped-text check passes at accessibility sizes |
| Dark Interface | **Yes** | Follows the system appearance; the watch is always dark |
| Differentiate Without Color Alone | **Yes** | Completed bullets carry ✓ as well as a lighter colour |
| Sufficient Contrast | **No** | Archived bullets are 2.23:1 in light mode, below the 4.5:1 minimum |
| Reduced Motion | **No** | The list still does a smooth move after a drop or an edit, even with Reduce Motion on |
| Captions | leave unticked | No audio or video |
| Audio Descriptions | leave unticked | No audio or video |

## Then
4. **Save** each device, then **Publish** the labels.
5. When one of the three **No**s gets fixed, come back and change it:
    - VoiceOver: after someone does the pass by ear
    - Sufficient Contrast: if archived bullets go above 4.5:1
    - Reduced Motion: once the list motion respects Reduce Motion