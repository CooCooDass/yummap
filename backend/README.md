# Yumap Backend API

FastAPI backend for the Wonju restaurant map/search/chat experience.

## Run locally

```powershell
python -m pip install -r ..\requirements.txt
$env:GOOGLE_CLOUD_PROJECT="project-68a630b4-e1e1-438a-b8e"
$env:GOOGLE_CLOUD_LOCATION="us"
$env:KAKAO_REST_API_KEY="..."
python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8001 --reload
```

The server keeps `SUPABASE_SERVICE_ROLE_KEY` server-side only. If Supabase env
vars are not set, it falls back to the final local JSON/JSONL files.

Optional production env:

```powershell
$env:SUPABASE_URL="https://aftqqlymsupnogbogmoy.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="..."
$env:GOOGLE_SERVICE_ACCOUNT_JSON="{...}"
$env:GEMINI_EMBEDDING_MODEL="gemini-embedding-002"
$env:GEMINI_CHAT_MODEL="gemini-3-flash-preview"
$env:KAKAO_REST_API_KEY="..."
$env:ALLOWED_ORIGINS="http://localhost:5173"
```

For Vercel, use `GOOGLE_SERVICE_ACCOUNT_JSON` instead of local gcloud auth.
Local gcloud credentials are not available inside deployed Functions.

## API

- `GET /health`
- `GET /categories`
- `GET /categories/{category_name}/restaurants?lat=&lng=&limit=`
- `GET /restaurants?lat=&lng=&limit=`
- `GET /restaurants/{rid}?lat=&lng=`
- `GET /search?q=&lat=&lng=&limit=`
- `GET /places/search?q=`
- `POST /chat`

`POST /chat` uses Gemini Embedding 2 for retrieval and Gemini 3 Flash for the
final Korean answer. The model response is parsed as structured JSON, then the
server aligns `answer`, `restaurants`, and itinerary-only `course_slots` to the
retrieved candidate IDs. If Gemini fails, the API returns a deterministic
fallback answer from the retrieved restaurant candidates.

`GET /health` uses lightweight Supabase count requests in production. The large
local JSONL embedding file is loaded only when Supabase is not configured or a
local fallback vector search is actually needed.

## Verify

```powershell
python -m pytest backend/tests -q
```
