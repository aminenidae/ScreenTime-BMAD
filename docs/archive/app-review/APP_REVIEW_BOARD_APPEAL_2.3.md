# Brain Coinz — Board of Appeal Letter (Guideline 2.3)

**Submit at:** https://developer.apple.com/contact/app-store/ → "Appeal App Review Decision"

---

## Appeal Letter (Copy-Paste)

```
Dear App Review Board,

I am appealing the fourth rejection of Brain Coinz (bundle ID:
i6dev.ScreenTimeRewards) under Guideline 2.3. All four rejections
cite UIRequiredDeviceCapabilities = ["arm64"] as inaccurate metadata.
I am unable to remove this key, and I can prove Apple's own toolchain
requires it.

THE CONTRADICTION:
When I removed this key to address the rejection, App Store Connect
validation failed with a hard error:

  "Your binary has a 64-bit architecture slice, so you must include
   the 'arm64' value for UIRequiredDeviceCapabilities."
  (Error ID: 59242661-b961-488a-b17c-27b17ac3bf52)

I attempted three separate removal approaches — removing it from
source, a build phase script, and full static Info.plist control.
Xcode 26.2 injects the key at archive-packaging level regardless.
App Store Connect then rejects any archive where it is absent.

The reviewer is requiring me to remove a key that App Store Connect
requires me to include. I cannot satisfy both simultaneously.

ARM64 DOES NOT RESTRICT MODERN DEVICES:
arm64 in UIRequiredDeviceCapabilities is an architecture declaration.
It does not restrict installation on arm64e devices (A12+, iPhone XS
and later). Apple's own device compatibility rules confirm this:
the App Store does not apply arm64 vs arm64e as an installation gate
for distribution builds. If it did, Apple's own validator would not
require it for distribution.

WHAT I AM ASKING:
A technical review of this specific contradiction by someone with
knowledge of App Store Connect validation requirements. The app
installs and runs correctly on all iOS 16.6+ devices.

I am available for a call to demonstrate the install and the
validation error live.

Respectfully,
[Developer Name]
i6dev.ScreenTimeRewards
```

**Character count:** ~1,450 / 2,000

---

## Supporting Evidence (Internal Reference)

- Full investigation documented in `docs/APP_REVIEW_RESPONSE_2.3.md`
- Error ID `59242661-b961-488a-b17c-27b17ac3bf52` obtained after Build 5 attempted removal
- Three removal approaches tested and confirmed bypassed by Xcode 26.2 injection
- Validator error screenshot/log available if needed for submission
