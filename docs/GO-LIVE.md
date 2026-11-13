# Going to production

Checklist for switching akwe from Plaid Sandbox to real bank data. Nothing here is needed while developing on Sandbox.

## 1. Link domain on GitHub Pages (free)

Plaid's OAuth return (most EU banks, incl. La Banque Postale) needs an `https` URL that iOS recognises as belonging to the app. A GitHub Pages **user site** provides it for free.

1. Create a public repo named exactly `<github-username>.github.io`.
   A project site (`<username>.github.io/<repo>`) does **not** work: Apple only reads the file at the domain root.
2. Add these files to the repo:

   `.nojekyll` (empty; without it GitHub Pages skips the `.well-known` folder)

   `.well-known/apple-app-site-association` (no file extension; replace `TEAMID` with your 10-character Apple Team ID):
   ```json
   { "applinks": { "details": [ { "appIDs": ["TEAMID.com.wakalo.akwe"], "components": [ { "/": "/plaid-oauth*" }, { "/": "/join*" } ] } ] } }
   ```

   `plaid-oauth/index.html` (fallback, only shown if the app isn't installed):
   ```html
   <!doctype html><meta charset="utf-8"><title>akwe</title><p>Return to the akwe app to finish connecting your bank.</p>
   ```
3. Repo Settings › Pages › deploy from the `main` branch.
4. Check `https://<username>.github.io/.well-known/apple-app-site-association` returns the JSON.

Then use `<username>.github.io` as the domain everywhere:

| Where | Value |
|---|---|
| Plaid Dashboard › Developers › API › Allowed redirect URIs | `https://<username>.github.io/plaid-oauth` |
| `backend/supabase/functions/.env` | `PLAID_REDIRECT_URI=https://<username>.github.io/plaid-oauth` |
| `backend/supabase/functions/.env` | `INVITE_BASE_URL=https://<username>.github.io/join` |
| `ios/App/Config/Secrets.xcconfig` | `AKWE_LINK_DOMAIN = <username>.github.io` |

A custom domain (~$10/yr) can be added later in the same Pages settings; update the four values above and rebuild.

## 2. Plaid production access

1. Dashboard: complete the company profile and the security questionnaire, and request **Transactions** for the countries you need (US, CA, FR/EU). Approval for EU institutions can take time, so apply early.
2. Copy the **Production** secret into `PLAID_SECRET` and set `PLAID_ENV=production`.

## 3. Push notifications

APNs keys work for both environments; nothing to change if already set up (see README › Apple). Release/TestFlight builds register as `production` automatically.

## 4. Deploy

```bash
cd backend && supabase secrets set --env-file ./supabase/functions/.env
```
```bash
cd ios && xcodegen
```
Rebuild the app, link a real bank, and confirm the OAuth bank flow returns to the app.
