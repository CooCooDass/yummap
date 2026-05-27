# Yumap

Wonju restaurant map and recommendation service. This repository is a monorepo
with a FastAPI backend and a Flutter web frontend.

## Repository Layout

- `backend/`: FastAPI app, recommendation logic, Gemini/Supabase/Kakao server clients, tests.
- `frontend/`: Flutter web app for map, restaurant list, detail panel, and chat UI.
- `data/supabase/`: final Supabase push data used for local fallback and DB rebuilds.
- `docs/API_CONTRACT.md`: frontend/backend integration contract.
- `app.py`: backend Vercel entrypoint.
- `vercel.json`: backend Vercel Function config.

Historical crawling scripts, raw outputs, intermediate files, and local tool
caches are kept under `legacy/` and ignored by Git.

## Backend Local Run

```powershell
python -m pip install -r requirements.txt
$env:KAKAO_REST_API_KEY="<kakao-rest-key>"
python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8001
```

Then open:

```text
http://127.0.0.1:8001/health
```

If Supabase env vars are not set, the backend falls back to `data/supabase/`.

## Frontend Local Run

Flutter must be installed locally. Start the backend first.

```powershell
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=KAKAO_JAVASCRIPT_KEY=<kakao-js-key>
```

The frontend reads restaurant/category/search/chat data only from the backend.
Kakao REST place search is proxied by the backend through `/places/search`.

## Verification

```powershell
python -m pytest backend/tests -q

cd frontend
flutter analyze
flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=KAKAO_JAVASCRIPT_KEY=<kakao-js-key>
```

## Deployment Model

Use two Vercel projects connected to the same GitHub repository:

- Backend project: repo root, using root `app.py` and `vercel.json`.
- Frontend project: root directory `frontend/`, using `frontend/vercel.json`.

Backend production env:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION
GOOGLE_SERVICE_ACCOUNT_JSON
GEMINI_EMBEDDING_MODEL
GEMINI_CHAT_MODEL
KAKAO_REST_API_KEY
ALLOWED_ORIGINS=https://your-frontend-domain.vercel.app
YUMAP_DISABLE_GEMINI=false
```

Frontend production env:

```text
API_BASE_URL=https://your-backend-domain.vercel.app
KAKAO_JAVASCRIPT_KEY=<kakao-js-key>
```

Do not commit real service keys. Rotate any key that has been exposed in chat,
logs, screenshots, or Git history.
