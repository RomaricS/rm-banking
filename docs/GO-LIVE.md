# Going to production

Checklist for switching akwe from Plaid Sandbox to real bank data. Nothing here is needed while developing on Sandbox.

## 1. Link domain on Netlify (free)

Plaid's OAuth return (most EU banks, incl. La Banque Postale) and shared-goal invite links need an `https` domain that iOS recognises as belonging to the app. The `web/` folder of this repo is that site, hosted free on Netlify at **`akwe-app.netlify.app`**.

What's in `web/`:
- `.well-known/apple-app-site-association`: tells iOS that `/plaid-oauth*` and `/join*` open the app (`LU3XP79638.com.wakalo.akwe`).
- `_headers`: serves that file as `application/json`.
- `plaid-oauth/` and `join/`: fallback pages, only shown when the app isn't installed.

Deploy it once:
1. app.netlify.com › Add new site › Import an existing project › GitHub › `rm-banking`.
2. Base directory `web`, build command empty, publish directory `web`. Deploy.
3. Site configuration › Change site name › `akwe-app`.
4. Check `https://akwe-app.netlify.app/.well-known/apple-app-site-association` returns the JSON.

Later pushes to `main` redeploy it automatically. If you'd rather not connect the repo, drag the `web` folder onto app.netlify.com/drop. Because it's a dot-folder, check that `.well-known` was uploaded.

The domain is used here:

| Where | Value |
|---|---|
| Plaid Dashboard › Developers › API › Allowed redirect URIs | `https://akwe-app.netlify.app/plaid-oauth` |
| `backend/supabase/functions/.env` | `PLAID_REDIRECT_URI=https://akwe-app.netlify.app/plaid-oauth` |
| `backend/supabase/functions/.env` | `INVITE_BASE_URL=https://akwe-app.netlify.app/join` |
| `ios/App/Config/Secrets.xcconfig` | `AKWE_LINK_DOMAIN = akwe-app.netlify.app` |

If you change the site name or add a custom domain, update these four values, edit nothing in the AASA file, and rebuild.

## 2. Plaid production access

1. Dashboard: complete the company profile and the security questionnaire, and request **Transactions** for the countries you need (US, CA, FR/EU). Approval for EU institutions can take time, so apply early.
2. Copy the **Production** secret into `PLAID_SECRET` and set `PLAID_ENV=production`. Put no comment on the same line: an inline `# …` becomes part of the value, and the backend then silently falls back to Sandbox.
3. Leave `PLAID_SKIP_WEBHOOK_VERIFY` empty in production.

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
