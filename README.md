# Yumap API

FastAPI backend for Wonju restaurant search, category browsing, and Gemini-based
restaurant recommendations.

## What Is Included

- `backend/`: FastAPI app, recommendation logic, Gemini/Supabase clients, tests.
- `data/supabase/`: final Supabase push data used for local fallback and DB rebuilds.
- `app.py`: Vercel entrypoint.
- `vercel.json`: Vercel Function config.

Historical crawling scripts, raw outputs, intermediate analysis files, and local
tool caches are kept under `legacy/` and ignored by Git.

## Local Run

```powershell
python -m pip install -r requirements.txt
python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

Then open:

```text
http://127.0.0.1:8000/health
```

## Test

```powershell
python -m pytest backend/tests -q
```

## Environment

Copy `.env.example` into your deployment provider and fill secrets there. Do not
commit real service keys.

For production, set:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_SERVICE_ACCOUNT_JSON`
- `GOOGLE_CLOUD_PROJECT`
- `GOOGLE_CLOUD_LOCATION`
- `GEMINI_EMBEDDING_MODEL`
- `GEMINI_CHAT_MODEL`
- `ALLOWED_ORIGINS`

See `backend/DEPLOYMENT.md` for deployment details.
