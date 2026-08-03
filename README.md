# Sift

Sift is a privacy-first iPhone app for scanning everyday products and understanding their ingredient lists at a glance.

## What it does

- Scans UPC, EAN, UPC-E, Code 128, and QR barcodes with the iPhone camera.
- Looks up food and personal-care products through Open Food Facts and Open Beauty Facts.
- Scores food, shampoo, skincare, cleaners, and other everyday items from 0–100.
- Explains every recognized ingredient pattern with a plain-language note.
- Lets a user paste an ingredient list when a barcode is missing or not found.
- Stores scan history locally on the device. No account and no Supabase dependency.

Scores are screening indicators based on the supplied ingredient text. They are not medical advice, allergy guarantees, or a substitute for reading the label or asking a qualified clinician.

## Build

Open `NetFare.xcodeproj` in Xcode 26 or later with an iOS SDK. The target currently uses iOS 18.0 as its minimum deployment target because iOS 24.0 is not a valid deployment target in the installed Apple SDK versioning.

The repository also contains `Package.swift` for running the Foundation-only scoring tests:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/sift-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/sift-swift-cache \
swift test --disable-sandbox
```

## Sample barcode

For a deterministic demo, enter `000000000001` in the app. It opens a sample cereal product without requiring a network request.

