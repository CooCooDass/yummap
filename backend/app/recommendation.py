from __future__ import annotations

import re
from typing import Any

from .data_store import DataStore
from .distance import haversine_km


GRADE_BOOST = {"gold": 1.0, "silver": 0.65, "bronze": 0.3}
QUERY_SYNONYMS = {
    "돈까스": "돈카츠",
    "돈까스집": "돈카츠",
    "한식집": "한식",
    "고기집": "고깃집",
    "브런치카페": "브런치",
}


def attach_distance(row: dict[str, Any], lat: float | None, lng: float | None) -> dict[str, Any]:
    item = dict(row)
    distance = haversine_km(lat, lng, item.get("latitude"), item.get("longitude"))
    item["distance_km"] = round(distance, 2) if distance is not None else None
    return item


def restaurant_summary(
    row: dict[str, Any],
    *,
    lat: float | None,
    lng: float | None,
    category_rank: int | None = None,
    matched_reason: str | None = None,
) -> dict[str, Any]:
    item = attach_distance(row, lat, lng)
    return {
        "rid": item["rid"],
        "name": item.get("name"),
        "grade": item.get("grade"),
        "category_rank": category_rank,
        "distance_km": item.get("distance_km"),
        "latitude": item.get("latitude"),
        "longitude": item.get("longitude"),
        "road_address": item.get("road_address"),
        "matched_reason": matched_reason,
    }


def list_category_restaurants(
    store: DataStore,
    category_name: str,
    *,
    lat: float | None,
    lng: float | None,
    limit: int,
) -> tuple[str, list[dict[str, Any]]]:
    category = store.get_category(category_name)
    if not category:
        return category_name, []
    category_rows = category.get("restaurants") or []
    rids = [row.get("rid") for row in category_rows if row.get("rid")]
    restaurants = store.get_restaurants_by_rids(rids)
    by_rid = {row["rid"]: row for row in restaurants}
    summaries = []
    for category_row in category_rows:
        rid = category_row.get("rid")
        restaurant = by_rid.get(rid)
        if restaurant:
            summaries.append(
                restaurant_summary(
                    restaurant,
                    lat=lat,
                    lng=lng,
                    category_rank=category_row.get("rank"),
                    matched_reason="category",
                )
            )
    return category["name"], summaries[:limit]


def search_restaurants(
    store: DataStore,
    query: str,
    *,
    lat: float | None,
    lng: float | None,
    limit: int,
) -> dict[str, Any]:
    category = store.get_category(query)
    if category:
        category_name, rows = list_category_restaurants(
            store,
            category["name"],
            lat=lat,
            lng=lng,
            limit=limit,
        )
        return {"query": query, "match_type": "category", "restaurants": rows, "category": category_name}

    rows = [
        restaurant_summary(row, lat=lat, lng=lng, matched_reason="restaurant")
        for row in store.search_restaurants_by_text(query, limit * 2)
    ]
    rows = sorted(rows, key=lambda row: _summary_sort_key(row))[:limit]
    return {"query": query, "match_type": "restaurant" if rows else "mixed", "restaurants": rows}


def retrieve_chat_candidates(
    store: DataStore,
    *,
    message: str,
    query_embedding: list[float] | None,
    lat: float | None,
    lng: float | None,
    limit: int = 12,
) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    intent = classify_intent(message)
    matches = store.match_documents(query_embedding, message, match_count=90 if intent == "itinerary" else 60)
    matches = _merge_direct_category_matches(store, message, matches)
    if not matches:
        matches = _structured_fallback_matches(store, message, 60)
    rids = [row["rid"] for row in matches]
    restaurants = store.get_restaurants_by_rids(rids)
    restaurants_by_rid = {row["rid"]: row for row in restaurants}
    match_by_rid = {row["rid"]: row for row in matches}

    reranked: list[dict[str, Any]] = []
    for rid in rids:
        restaurant = restaurants_by_rid.get(rid)
        if not restaurant:
            continue
        candidate = attach_distance(restaurant, lat, lng)
        match = match_by_rid.get(rid, {})
        candidate["semantic_similarity"] = float(match.get("similarity") or 0.0)
        candidate["keyword_boost"] = keyword_match_boost(message, candidate, match.get("search_document") or "")
        candidate["rerank_score"] = rerank_score(candidate)
        reranked.append(candidate)

    reranked = sorted(reranked, key=lambda row: row["rerank_score"], reverse=True)
    reranked = dedupe_chat_candidates(reranked)
    if intent == "itinerary":
        reranked = diversify_for_itinerary(reranked)

    debug = {
        "intent": intent,
        "candidate_count": len(reranked),
        "used_vector_embedding": query_embedding is not None,
    }
    return intent, reranked[:limit], debug


def dedupe_chat_candidates(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_name: dict[str, dict[str, Any]] = {}
    for candidate in candidates:
        key = str(candidate.get("name") or candidate.get("rid") or "").strip().lower()
        if not key:
            continue
        existing = by_name.get(key)
        if existing is None or _candidate_quality_key(candidate) > _candidate_quality_key(existing):
            by_name[key] = candidate
    return sorted(by_name.values(), key=lambda row: row.get("rerank_score") or 0.0, reverse=True)


def align_candidates_to_llm_payload(
    candidates: list[dict[str, Any]],
    payload: dict[str, Any] | None,
    intent: str,
) -> tuple[list[dict[str, Any]], dict[str, str], list[dict[str, str]]]:
    by_rid = {row["rid"]: row for row in candidates}
    reasons: dict[str, str] = {}
    course_slots: list[dict[str, str]] = []
    if not payload:
        selected = candidates[:8]
        if intent == "itinerary":
            course_slots = default_course_slots(selected)
        return selected, reasons, course_slots

    raw_reasons = payload.get("restaurant_reasons")
    if isinstance(raw_reasons, dict):
        reasons = {str(rid): str(reason) for rid, reason in raw_reasons.items()}

    selected: list[dict[str, Any]] = []
    seen: set[str] = set()
    raw_ids = payload.get("restaurant_ids")
    if isinstance(raw_ids, list):
        for rid in raw_ids:
            rid_key = str(rid)
            if rid_key in by_rid and rid_key not in seen:
                selected.append(by_rid[rid_key])
                seen.add(rid_key)

    raw_slots = payload.get("course_slots")
    if intent == "itinerary" and isinstance(raw_slots, list):
        for slot in raw_slots:
            if not isinstance(slot, dict):
                continue
            rid = str(slot.get("rid") or "")
            if rid not in by_rid:
                continue
            label = str(slot.get("label") or "")
            if not label:
                continue
            course_slots.append({"label": label, "rid": rid, "name": by_rid[rid].get("name") or ""})
            if rid not in seen:
                selected.append(by_rid[rid])
                seen.add(rid)

    if not selected:
        selected = candidates[:8]
    elif len(selected) < min(5, len(candidates)):
        for candidate in candidates:
            if candidate["rid"] not in seen:
                selected.append(candidate)
                seen.add(candidate["rid"])
            if len(selected) >= 8:
                break

    if intent == "itinerary" and not course_slots:
        course_slots = default_course_slots(selected)

    return selected[:8], reasons, course_slots


def default_course_slots(candidates: list[dict[str, Any]]) -> list[dict[str, str]]:
    labels = ["Day 1 점심", "Day 1 카페/간식", "Day 1 저녁", "Day 2 아침/브런치", "Day 2 점심"]
    slots = []
    for label, candidate in zip(labels, candidates):
        slots.append({"label": label, "rid": candidate["rid"], "name": candidate.get("name") or ""})
    return slots


def _structured_fallback_matches(
    store: DataStore,
    message: str,
    match_count: int,
) -> list[dict[str, Any]]:
    search_text = message
    replacements = {
        "돈까스집": "돈까스",
        "한식집": "한식",
        "카페": "카페",
        "gold": "gold",
        "골드": "gold",
    }
    for source, target in replacements.items():
        if source in message:
            search_text = target
            break

    rows = store.search_restaurants_by_text(search_text, match_count)
    if not rows:
        rows = sorted(
            store.list_restaurants(),
            key=lambda row: {"gold": 0, "silver": 1, "bronze": 2}.get(str(row.get("grade") or ""), 3),
        )[:match_count]

    return [
        {
            "rid": row["rid"],
            "name": row.get("name"),
            "grade": row.get("grade"),
            "search_document": " ".join(row.get("categories") or []),
            "similarity": 0.5,
        }
        for row in rows
    ]


def classify_intent(message: str) -> str:
    text = message.lower()
    if any(token in text for token in ["코스", "1박", "2박", "일정", "여행"]):
        return "itinerary"
    if any(token in text for token in ["근처", "가까운", "주변"]):
        return "nearby_recommendation"
    return "restaurant_recommendation"


def keyword_match_boost(message: str, restaurant: dict[str, Any], search_document: str) -> float:
    text = " ".join(
        [
            restaurant.get("name") or "",
            " ".join(restaurant.get("categories") or []),
            " ".join(restaurant.get("meal_types") or []),
            " ".join(restaurant.get("recommendation_tags") or []),
            search_document,
        ]
    ).lower()
    tokens = _query_tokens(message)
    if not tokens:
        return 0.0
    hits = sum(1 for token in tokens if token in text)
    return min(1.0, hits / max(len(tokens), 1))


def _merge_direct_category_matches(
    store: DataStore,
    message: str,
    matches: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    normalized_message = _normalize_query_text(message)
    direct_category = None
    for category in store.list_categories():
        category_name = category["name"]
        query = category.get("query") or ""
        if category_name in normalized_message or category_name in query and category_name in normalized_message:
            direct_category = category
            break
    if not direct_category:
        return matches

    category_rows = direct_category.get("restaurants") or []
    direct_matches = []
    for index, category_row in enumerate(category_rows[:30]):
        rid = category_row.get("rid")
        if not rid:
            continue
        direct_matches.append(
            {
                "rid": rid,
                "name": category_row.get("name"),
                "grade": category_row.get("grade"),
                "search_document": direct_category["name"],
                "similarity": max(0.92, 1.0 - index * 0.01),
            }
        )

    seen = set()
    merged = []
    for row in direct_matches + matches:
        rid = row.get("rid")
        if rid and rid not in seen:
            seen.add(rid)
            merged.append(row)
    return merged


def _query_tokens(message: str) -> list[str]:
    tokens: set[str] = set()
    for raw_token in re.split(r"[\s,./]+", message.lower()):
        token = raw_token.strip()
        if len(token) < 2:
            continue
        tokens.add(token)
        tokens.add(QUERY_SYNONYMS.get(token, token))
        for suffix in ("집", "식당", "맛집", "요리"):
            if token.endswith(suffix) and len(token) > len(suffix) + 1:
                stripped = token[: -len(suffix)]
                tokens.add(stripped)
                tokens.add(QUERY_SYNONYMS.get(stripped, stripped))
    return list(tokens)


def _normalize_query_text(message: str) -> str:
    text = message.lower()
    for source, target in QUERY_SYNONYMS.items():
        text = text.replace(source, target)
    return text


def rerank_score(candidate: dict[str, Any]) -> float:
    similarity = max(0.0, min(1.0, float(candidate.get("semantic_similarity") or 0.0)))
    grade = GRADE_BOOST.get(str(candidate.get("grade") or "").lower(), 0.2)
    keyword = max(0.0, min(1.0, float(candidate.get("keyword_boost") or 0.0)))
    distance = distance_boost(candidate.get("distance_km"))
    return 0.65 * similarity + 0.15 * grade + 0.10 * keyword + 0.10 * distance


def distance_boost(distance_km: float | None) -> float:
    if distance_km is None:
        return 0.5
    if distance_km <= 1:
        return 1.0
    if distance_km <= 3:
        return 0.8
    if distance_km <= 5:
        return 0.6
    if distance_km <= 10:
        return 0.4
    return 0.2


def diversify_for_itinerary(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    seen_categories: set[str] = set()
    for candidate in candidates:
        categories = candidate.get("categories") or []
        primary = categories[0] if categories else candidate.get("grade") or "unknown"
        if primary not in seen_categories or len(selected) < 3:
            selected.append(candidate)
            seen_categories.add(primary)
        if len(selected) >= 12:
            break
    if len(selected) < 12:
        selected_rids = {row["rid"] for row in selected}
        selected.extend(row for row in candidates if row["rid"] not in selected_rids)
    return selected[:12]


def deterministic_answer(message: str, intent: str, candidates: list[dict[str, Any]]) -> str:
    if not candidates:
        return "조건에 맞는 식당 후보를 찾지 못했습니다. 검색어를 조금 더 구체적으로 입력해 주세요."
    if intent == "itinerary":
        labels = ["Day 1 점심", "Day 1 카페/간식", "Day 1 저녁", "Day 2 아침/브런치", "Day 2 점심"]
        lines = ["제공된 원주 식당 데이터 기준으로 식당 중심 코스를 구성했습니다."]
        for label, candidate in zip(labels, candidates):
            lines.append(f"- {label}: {candidate['name']} ({candidate.get('grade')})")
        lines.append("추천 식당 목록:")
        for index, candidate in enumerate(candidates[:8], start=1):
            lines.append(f"{index}. {candidate['name']} - {candidate.get('grade')} 등급, 질문 관련성이 높은 후보입니다.")
        return "\n".join(lines)

    lines = [f"'{message}'에 맞춰 데이터에서 관련성이 높은 식당을 골랐습니다."]
    lines.append("추천 식당 목록:")
    for index, candidate in enumerate(candidates[:8], start=1):
        distance = (
            f", 약 {candidate['distance_km']}km"
            if candidate.get("distance_km") is not None
            else ""
        )
        categories = ", ".join(candidate.get("categories") or []) or "관련 카테고리"
        lines.append(
            f"{index}. {candidate['name']} - {candidate.get('grade')} 등급{distance}. {categories} 기준으로 추천합니다."
        )
    return "\n".join(lines)


def chat_restaurant_reason(candidate: dict[str, Any]) -> str:
    categories = ", ".join(candidate.get("categories") or [])
    grade = candidate.get("grade") or "등급 정보 없음"
    if categories:
        return f"{categories} 관련성이 있고 {grade} 등급입니다."
    return f"질문과의 검색 관련성이 높고 {grade} 등급입니다."


def _summary_sort_key(row: dict[str, Any]) -> tuple[int, float]:
    grade_value = {"gold": 0, "silver": 1, "bronze": 2}.get(str(row.get("grade") or ""), 3)
    distance = row.get("distance_km")
    return grade_value, distance if distance is not None else 9999.0


def _candidate_quality_key(candidate: dict[str, Any]) -> tuple[float, int, float]:
    grade_value = {"gold": 3, "silver": 2, "bronze": 1}.get(str(candidate.get("grade") or ""), 0)
    distance = candidate.get("distance_km")
    distance_value = -(distance if distance is not None else 9999.0)
    return float(candidate.get("rerank_score") or 0.0), grade_value, distance_value
