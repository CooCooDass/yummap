from __future__ import annotations

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .data_store import DataStore
from .gemini import GeminiClient, GeminiError
from .models import (
    CategoryRestaurantsResponse,
    CategorySummary,
    ChatRequest,
    ChatResponse,
    ChatRestaurant,
    PlaceSearchResponse,
    RestaurantDetail,
    RestaurantSummary,
    SearchResponse,
)
from .places import PlaceSearchError, search_kakao_place
from .recommendation import (
    align_candidates_to_llm_payload,
    build_display_answer,
    chat_restaurant_reason,
    deterministic_answer,
    distance_label,
    grade_icon,
    list_category_restaurants,
    restaurant_detail_path,
    restaurant_summary,
    retrieve_chat_candidates,
    search_restaurants,
)


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Yumap Restaurant API", version="0.1.0")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.settings = settings
    app.state.store = DataStore(settings)
    app.state.gemini = GeminiClient(settings)

    @app.get("/health")
    def health(store: DataStore = Depends(get_store)) -> dict[str, object]:
        return {
            "ok": True,
            **store.health(),
            "embedding_model": settings.embedding_model,
            "chat_model": settings.chat_model,
        }

    @app.get("/categories", response_model=list[CategorySummary])
    def categories(store: DataStore = Depends(get_store)) -> list[dict[str, object]]:
        return [
            {
                "name": row["name"],
                "query": row.get("query"),
                "total_count": row.get("total_count"),
                "main_page_index": row.get("main_page_index"),
            }
            for row in store.list_categories()
        ]

    @app.get("/categories/{category_name}/restaurants", response_model=CategoryRestaurantsResponse)
    def category_restaurants(
        category_name: str,
        lat: float | None = None,
        lng: float | None = None,
        limit: int = Query(default=50, ge=1, le=200),
        store: DataStore = Depends(get_store),
    ) -> dict[str, object]:
        resolved_category, rows = list_category_restaurants(
            store,
            category_name,
            lat=lat,
            lng=lng,
            limit=limit,
        )
        if not rows:
            raise HTTPException(status_code=404, detail="category not found or empty")
        return {"category": resolved_category, "restaurants": rows}

    @app.get("/restaurants", response_model=list[RestaurantSummary])
    def restaurants(
        lat: float | None = None,
        lng: float | None = None,
        limit: int = Query(default=2000, ge=1, le=2500),
        store: DataStore = Depends(get_store),
    ) -> list[dict[str, object]]:
        rows = [restaurant_summary(row, lat=lat, lng=lng) for row in store.list_restaurants()]
        grade_order = {"gold": 0, "silver": 1, "bronze": 2}
        rows.sort(
            key=lambda row: (
                row.get("distance_km") is None,
                row.get("distance_km") or 999999,
                grade_order.get(str(row.get("grade") or "").lower(), 9),
                str(row.get("name") or ""),
            )
        )
        return rows[:limit]

    @app.get("/restaurants/{rid}", response_model=RestaurantDetail)
    def restaurant_detail(
        rid: str,
        lat: float | None = None,
        lng: float | None = None,
        store: DataStore = Depends(get_store),
    ) -> dict[str, object]:
        row = store.get_restaurant(rid)
        if not row:
            raise HTTPException(status_code=404, detail="restaurant not found")
        return restaurant_summary(row, lat=lat, lng=lng) | {
            "jibun_address": row.get("jibun_address"),
            "phone": row.get("phone"),
            "hours": row.get("hours"),
            "menus": row.get("menus"),
            "categories": row.get("categories") or [],
            "meal_types": row.get("meal_types") or [],
            "recommendation_tags": row.get("recommendation_tags") or [],
        }

    @app.get("/search", response_model=SearchResponse)
    def search(
        q: str = Query(min_length=1),
        lat: float | None = None,
        lng: float | None = None,
        limit: int = Query(default=30, ge=1, le=100),
        store: DataStore = Depends(get_store),
    ) -> dict[str, object]:
        result = search_restaurants(store, q, lat=lat, lng=lng, limit=limit)
        return {
            "query": result["query"],
            "match_type": result["match_type"],
            "restaurants": result["restaurants"],
        }

    @app.get("/places/search", response_model=PlaceSearchResponse)
    def place_search(q: str = Query(min_length=1)) -> dict[str, object]:
        if not settings.kakao_rest_api_key:
            raise HTTPException(status_code=503, detail="KAKAO_REST_API_KEY is not configured")
        try:
            result = search_kakao_place(settings.kakao_rest_api_key, q)
        except PlaceSearchError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        if not result:
            raise HTTPException(status_code=404, detail="place not found")
        return result

    @app.post("/chat", response_model=ChatResponse)
    def chat(
        request: ChatRequest,
        store: DataStore = Depends(get_store),
        gemini: GeminiClient = Depends(get_gemini),
    ) -> dict[str, object]:
        try:
            query_embedding = gemini.embed_query(request.message)
            embedding_error = None
        except GeminiError as exc:
            query_embedding = None
            embedding_error = str(exc)

        intent, candidates, debug = retrieve_chat_candidates(
            store,
            message=request.message,
            query_embedding=query_embedding,
            lat=request.lat,
            lng=request.lng,
        )

        try:
            llm_payload = gemini.generate_chat_payload(
                message=request.message,
                candidates=candidates[:10],
                intent=intent,
            )
            raw_answer = (
                llm_payload.get("answer_intro") or llm_payload.get("answer")
                if isinstance(llm_payload, dict)
                else None
            )
            answer = raw_answer if isinstance(raw_answer, str) else None
            llm_error = None
        except GeminiError as exc:
            llm_payload = None
            answer = None
            llm_error = str(exc)

        if not answer:
            answer = deterministic_answer(request.message, intent, candidates)

        selected_candidates, llm_reasons, course_slots = align_candidates_to_llm_payload(
            candidates,
            llm_payload,
            intent,
        )
        restaurants = [
            ChatRestaurant(
                rid=row["rid"],
                name=row["name"],
                grade=row.get("grade"),
                grade_icon=grade_icon(row.get("grade")),
                distance_km=row.get("distance_km"),
                distance_label=distance_label(row.get("distance_km")),
                reason=llm_reasons.get(row["rid"]) or chat_restaurant_reason(row),
                detail_path=restaurant_detail_path(row["rid"]),
                latitude=row.get("latitude"),
                longitude=row.get("longitude"),
            )
            for row in selected_candidates
        ]
        display_answer = build_display_answer(answer, restaurants)
        debug.update(
            {
                "used_embedding_model": settings.embedding_model,
                "used_llm_model": settings.chat_model,
                "embedding_error": embedding_error,
                "llm_error": llm_error,
            }
        )
        return {
            "answer": answer,
            "display_answer": display_answer,
            "restaurants": restaurants,
            "course_slots": course_slots,
            "retrieval_debug": debug,
        }

    return app


def get_store() -> DataStore:
    return app.state.store


def get_gemini() -> GeminiClient:
    return app.state.gemini


app = create_app()
