from __future__ import annotations

import os

os.environ["YUMAP_DISABLE_GEMINI"] = "1"
os.environ.pop("SUPABASE_SERVICE_ROLE_KEY", None)

from fastapi.testclient import TestClient

from backend.app.main import app


client = TestClient(app)


def test_health_counts() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["restaurants"] == 1989
    assert payload["categories"] == 45


def test_categories() -> None:
    response = client.get("/categories")
    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 45
    assert {"name", "query", "total_count", "main_page_index"} <= set(payload[0])


def test_category_restaurants_keeps_rank() -> None:
    response = client.get("/categories/막국수/restaurants?lat=37.3422&lng=127.9202&limit=5")
    assert response.status_code == 200
    payload = response.json()
    ranks = [row["category_rank"] for row in payload["restaurants"]]
    assert ranks == sorted(ranks)
    assert all(row["distance_km"] is not None for row in payload["restaurants"])


def test_restaurant_detail() -> None:
    category_response = client.get("/categories/막국수/restaurants?limit=1")
    rid = category_response.json()["restaurants"][0]["rid"]
    response = client.get(f"/restaurants/{rid}")
    assert response.status_code == 200
    payload = response.json()
    assert payload["rid"] == rid
    assert isinstance(payload["categories"], list)


def test_search_category_and_restaurant() -> None:
    category_response = client.get("/search?q=돈까스&limit=10")
    assert category_response.status_code == 200
    assert category_response.json()["restaurants"]

    restaurant_response = client.get("/search?q=막국수&limit=10")
    assert restaurant_response.status_code == 200
    assert restaurant_response.json()["restaurants"]


def test_search_aliases_cover_common_food_terms() -> None:
    aliases = ["돈가스", "커피전문점", "중국집", "스시", "고기집", "파스타", "쌀국수"]
    for alias in aliases:
        response = client.get(f"/search?q={alias}&limit=5")
        assert response.status_code == 200
        payload = response.json()
        assert payload["match_type"] == "category"
        assert payload["restaurants"]


def test_chat_scenarios() -> None:
    scenarios = [
        "원주에서 맛있는 돈까스집 추천해줘",
        "근처 카페 추천해줘",
        "가족이랑 갈만한 한식집 알려줘",
        "원주 1박2일 식당 코스 추천해줘",
        "gold 식당 위주로 추천해줘",
    ]
    for message in scenarios:
        response = client.post(
            "/chat",
            json={"message": message, "lat": 37.3422, "lng": 127.9202},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["answer"]
        assert payload["restaurants"]
        assert all(row["rid"] and row["name"] for row in payload["restaurants"])


def test_chat_dedupes_restaurant_names_and_course_slots_are_intent_only() -> None:
    response = client.post(
        "/chat",
        json={"message": "가족이랑 갈만한 한식집 알려줘", "lat": 37.3422, "lng": 127.9202},
    )
    payload = response.json()
    names = [row["name"] for row in payload["restaurants"]]
    assert len(names) == len(set(names))
    assert payload["course_slots"] == []

    itinerary_response = client.post(
        "/chat",
        json={"message": "원주 1박2일 식당 코스 추천해줘", "lat": 37.3422, "lng": 127.9202},
    )
    itinerary_payload = itinerary_response.json()
    assert itinerary_payload["course_slots"]
