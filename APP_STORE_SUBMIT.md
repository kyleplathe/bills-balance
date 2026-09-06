# TestFlight and App Store submit

Code for v1 is archive-ready after a clean Release build. Apple still requires you to finish these in App Store Connect and Xcode.

## Before upload

1. Confirm the Apple Developer Program membership is active (Team `3GG234YCUT`).
2. In Certificates, Identifiers & Profiles, the App ID `com.kyle.billsandbalance` exists. Do **not** add iCloud / CloudKit for this release.
3. Create the App Store Connect app if it does not exist: name **Bills & Balance**, bundle ID `com.kyle.billsandbalance`, SKU e.g. `billsandbalance`.
4. Paste listing copy from [APP_STORE_LISTING.md](APP_STORE_LISTING.md). Privacy URL must be publicly reachable.
5. If `https://github.com/kyleplathe/bills-balance/blob/main/PRIVACY.md` is behind a private repo, publish [PRIVACY.md](PRIVACY.md) on a public page first.

## Archive status

A Release archive for `com.kyle.billsandbalance` (1.0 / 1) was built successfully from this project (`generic/platform=iOS`). Upload and TestFlight still happen in Xcode Organizer on your Mac:

1. Open the project in Xcode → Product → Archive (or Window → Organizer and select the existing archive).
2. Distribute App → App Store Connect → Upload.
3. After processing, add the build to TestFlight, install on iPhone and iPad, then walk [APP_STORE_QA.md](APP_STORE_QA.md).
4. Submit for review using [APP_STORE_LISTING.md](APP_STORE_LISTING.md).

Do not enable iCloud / CloudKit on the App ID for this release.

## TestFlight

1. Internal testing: add yourself, install on iPhone and iPad.
2. Walk [APP_STORE_QA.md](APP_STORE_QA.md).
3. External testing is optional for 1.0.

## Submit for review

1. Select the processed build.
2. Attach screenshots (6.7", 6.1", iPad 13").
3. Paste **Review notes** from [APP_STORE_LISTING.md](APP_STORE_LISTING.md).
4. Export compliance: No (exempt / HTTPS only).
5. Submit.
