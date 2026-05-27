# Deployment Checklist

This backend is ready to deploy as a FastAPI app on Vercel.

Vercel's FastAPI support detects a root `app.py` exporting `app`, and turns the
application into a single Vercel Function. The project also includes
`vercel.json` to keep long-running chat requests under a 60 second function
limit and to exclude crawler/intermediate files from the bundle.

## Required Environment Variables

Set these in Vercel Project Settings before production deployment:

```text
SUPABASE_URL=https://aftqqlymsupnogbogmoy.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
GOOGLE_CLOUD_PROJECT=project-68a630b4-e1e1-438a-b8e
GOOGLE_CLOUD_LOCATION=us
GOOGLE_SERVICE_ACCOUNT_JSON=<single-line rotated service account JSON>
GEMINI_EMBEDDING_MODEL=gemini-embedding-002
GEMINI_CHAT_MODEL=gemini-3-flash-preview
KAKAO_REST_API_KEY=...
ALLOWED_ORIGINS=https://your-frontend-domain.vercel.app
```

`GOOGLE_SERVICE_ACCOUNT_JSON` should be a single-line JSON string for a Google
Cloud service account with Vertex AI / Agent Platform access. Local gcloud login
works on your machine, but it will not exist inside Vercel Functions.

## Smoke Tests After Deploy

```powershell
Invoke-RestMethod https://your-api-domain.vercel.app/health

$body = @{ message='원주에서 맛있는 돈까스집 추천해줘'; lat=37.3422; lng=127.9202 } | ConvertTo-Json
Invoke-RestMethod https://your-api-domain.vercel.app/chat `
  -Method Post `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body
```

## Security Notes

- Never expose `SUPABASE_SERVICE_ROLE_KEY` to the browser.
- Never expose `KAKAO_REST_API_KEY` to the browser. The frontend uses only
  `KAKAO_JAVASCRIPT_KEY`; local place search is proxied through `/places/search`.
- Keep frontend requests pointed at this backend, not directly at Supabase.
- Before public launch, enable rate limiting or Vercel Firewall rules for
  `/chat` because every request can call Gemini.
- Supabase RLS should still be reviewed. The backend is safe with service-role
  access only if the service key remains server-side.
