# Yumap Frontend-Backend Contract

This document is the integration contract for frontend work. The FastAPI backend is the source of truth for field names, response shapes, search behavior, and chat response rendering.

## Ownership

- Backend owns restaurant data, category data, search, place lookup, recommendations, chat retrieval, Gemini calls, Supabase access, and all server-side secrets.
- Frontend owns layout, map rendering, list/detail/chat UI state, and user interactions.
- Frontend must not read local restaurant/category JSON as production data.
- Frontend must not call Supabase, Gemini, or Kakao REST APIs directly.

## Environment Variables

Backend-only:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION
GOOGLE_SERVICE_ACCOUNT_JSON
GOOGLE_OAUTH_ACCESS_TOKEN
GEMINI_EMBEDDING_MODEL
GEMINI_CHAT_MODEL
KAKAO_REST_API_KEY
ALLOWED_ORIGINS
YUMAP_DISABLE_GEMINI
```

Frontend-only:

```text
API_BASE_URL
KAKAO_JAVASCRIPT_KEY
```

`KAKAO_JAVASCRIPT_KEY` is allowed in the browser bundle. `KAKAO_REST_API_KEY` is not.

## Backend Endpoints Used By Frontend

### `GET /health`

Used for smoke checks. Important fields:

```json
{
  "ok": true,
  "source": "supabase",
  "restaurants": 1989,
  "categories": 45
}
```

### `GET /categories`

Returns category metadata:

```json
[
  {
    "name": "막국수",
    "query": "막국수",
    "total_count": 10,
    "main_page_index": 1
  }
]
```

### `GET /restaurants?lat=&lng=&limit=`

Primary frontend list source. Each restaurant summary may include:

```json
{
  "rid": "abc",
  "name": "식당명",
  "grade": "gold",
  "category_rank": null,
  "distance_km": 0.25,
  "latitude": 37.3422,
  "longitude": 127.9202,
  "road_address": "강원 원주시 ...",
  "categories": ["일식", "돈카츠"],
  "meal_types": ["점심"],
  "recommendation_tags": ["가족"],
  "matched_reason": null
}
```

### `GET /restaurants/{rid}?lat=&lng=`

Detail panel source. It extends the summary shape with:

```json
{
  "jibun_address": "강원 원주시 ...",
  "phone": "033-...",
  "hours": {},
  "menus": []
}
```

### `GET /categories/{category_name}/restaurants?lat=&lng=&limit=`

Returns category-scoped rankings:

```json
{
  "category": "막국수",
  "restaurants": []
}
```

### `GET /search?q=&lat=&lng=&limit=`

Backend text/category search. Use this when frontend needs server-ranked search results.

### `GET /places/search?q=`

Backend proxy for Kakao Local keyword search. Returns:

```json
{
  "lat": 37.342218,
  "lng": 127.919581,
  "name": "원주시청"
}
```

Frontend should treat `404` and `503` as "place not available/not found" and show a friendly message.

### `POST /chat`

Request:

```json
{
  "message": "원주에서 맛있는 돈까스집 추천해줘",
  "lat": 37.3422,
  "lng": 127.9202,
  "history": []
}
```

Response:

```json
{
  "answer": "원주에서 돈까스로 유명한 ... 추천합니다.",
  "display_answer": "...",
  "restaurants": [
    {
      "rid": "abc",
      "name": "식당명",
      "grade": "gold",
      "grade_icon": "🥇",
      "distance_km": 0.25,
      "distance_label": "0.25km",
      "reason": "일식 돈카츠가 좋은 골드 등급 식당입니다.",
      "detail_path": "/restaurants/abc",
      "latitude": 37.3422,
      "longitude": 127.9202
    }
  ],
  "course_slots": [],
  "retrieval_debug": {}
}
```

Frontend chat rendering should use `answer` plus `restaurants[]`. `display_answer` is available for markdown-like fallback, but custom UI cards/lists should use structured fields.

## Grade Rules

- Valid values: `gold`, `silver`, `bronze`.
- Display icons:
  - `gold`: 🥇
  - `silver`: 🥈
  - `bronze`: 🥉
- Pins and badges must be derived from `grade`.
- Do not use `best_grade`, `score`, `rating`, or locally inferred grade fields in frontend production UI.

## Frontend Merge Checklist

Before merging frontend changes:

- No production dependency on `assets/restaurants.json` or `assets/categories.json`.
- No `best_grade`, `bestGrade`, dummy `rating`, or hardcoded restaurant fixture data.
- No frontend usage of `KAKAO_REST_API_KEY`.
- `flutter analyze` passes.
- `flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=KAKAO_JAVASCRIPT_KEY=<js-key>` passes.
- Local browser smoke test passes for map, list, detail, category filter, place search, and chat.

## Backend Merge Checklist

Before merging backend changes:

- `python -m pytest backend/tests -q` passes.
- Existing response fields remain backward-compatible unless frontend is updated in the same commit.
- New secrets are added only as environment variables and documented in `.env.example`.
- Service keys are never printed in logs or returned to the browser.
