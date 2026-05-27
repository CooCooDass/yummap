# Yumap Frontend

Flutter web client for Yumap.

## Local Run

Start the backend first at `http://127.0.0.1:8001`, then run:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=KAKAO_JAVASCRIPT_KEY=<kakao-js-key>
```

## Vercel

Create a separate Vercel project with root directory `frontend/`.

Required environment variables:

```text
API_BASE_URL=https://your-backend.vercel.app
KAKAO_JAVASCRIPT_KEY=<kakao-js-key>
```

Do not add `KAKAO_REST_API_KEY` to the frontend project. Place search goes
through the backend `/places/search` endpoint.
