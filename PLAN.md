# Sift implementation plan

## Product promise

Make grocery and personal-care shopping easier by turning a barcode and ingredient list into a clear, explainable signal in seconds.

## v1 shipped in this repository

1. One-tap barcode scanning with camera and manual fallback.
2. Open Food Facts and Open Beauty Facts lookup with timeouts and graceful offline behavior.
3. Local sample catalog so the demo works without network access.
4. Transparent 0–100 ingredient screening score with category-aware flags.
5. Food, beauty, household, pet, and everyday-item categories.
6. Paste-an-ingredient-list fallback for products missing from the database.
7. On-device history, delete-all controls, and a methodology explanation.
8. Camera permission copy and privacy disclosure suitable for TestFlight review.

## Scoring guardrails

- Never call a product medically safe or unsafe.
- Show the exact ingredient text used for the result.
- Explain each recognized flag in plain language.
- Return “Not enough data” when the source has no usable ingredient list.
- Keep the score deterministic and covered by unit tests.

## Follow-ups

- Add label-photo OCR using Vision.
- Add allergen profiles and dietary preferences locally.
- Add price and pack-size comparison without requiring an account.
- Replace heuristic flags with a reviewed, versioned ruleset and source citations.

