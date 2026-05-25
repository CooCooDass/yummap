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
    RestaurantDetail,
    SearchResponse,
)
from .recommendation import (
    align_candidates_to_llm_payload,
    chat_restaurant_reason,
    deterministic_answer,
    list_category_restaurants,
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
            answer = llm_payload.get("answer") if isinstance(llm_payload, dict) else None
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
                distance_km=row.get("distance_km"),
                reason=llm_reasons.get(row["rid"]) or chat_restaurant_reason(row),
                latitude=row.get("latitude"),
                longitude=row.get("longitude"),
            )
            for row in selected_candidates
        ]
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
