# Data analysis tools

Read-only scripts to export and analyze the app's backend data.

- `firestore-export.js` — dumps every Firestore collection (and subcollections)
  to JSON and writes a `SUMMARY.md` with subscription tallies. **Works today.**
- `revenuecat-export.js` — pulls products/entitlements/offerings from the
  RevenueCat v2 REST API. **Requires the session network policy to allow
  `api.revenuecat.com`** (blocked by default).

## Credentials (never commit these)

Provide credentials via environment variables / session secrets, not files in
the repo:

| Variable | Used by | What it is |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | firestore | Service-account JSON (string or base64) |
| `GOOGLE_APPLICATION_CREDENTIALS` | firestore | …or a path to that JSON file |
| `FIREBASE_PROJECT_ID` | firestore | Optional project-id override |
| `RC_API_KEY` | revenuecat | RevenueCat v2 secret key (read scope) |
| `RC_PROJECT_ID` | revenuecat | RevenueCat project id |

## Run

```bash
cd tools/data-analysis
npm install
npm run firestore      # writes ./export/*.json + SUMMARY.md
npm run revenuecat     # only if api.revenuecat.com is allowed
```

The `export/` directory is git-ignored — it contains live data and must not be
committed.
