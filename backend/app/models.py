from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class RestaurantSummary(BaseModel):
    rid: str
    name: str
    grade: str | None = None
    category_rank: int | None = None
    distance_km: float | None = None
    latitude: float | None = None
    longitude: float | None = None
    road_address: str | None = None
    categories: list[str] = Field(default_factory=list)
    meal_types: list[str] = Field(default_factory=list)
    recommendation_tags: list[str] = Field(default_factory=list)
    matched_reason: str | None = None


class CategorySummary(BaseModel):
    name: str
    query: str | None = None
    total_count: int | None = None
    main_page_index: int | None = None


class CategoryRestaurantsResponse(BaseModel):
    category: str
    restaurants: list[RestaurantSummary]


class SearchResponse(BaseModel):
    query: str
    match_type: str
    restaurants: list[RestaurantSummary]


class PlaceSearchResponse(BaseModel):
    lat: float
    lng: float
    name: str


class RestaurantDetail(BaseModel):
    rid: str
    name: str
    road_address: str | None = None
    jibun_address: str | None = None
    phone: str | None = None
    hours: Any = None
    menus: Any = None
    latitude: float | None = None
    longitude: float | None = None
    grade: str | None = None
    categories: list[str] = Field(default_factory=list)
    meal_types: list[str] = Field(default_factory=list)
    recommendation_tags: list[str] = Field(default_factory=list)
    distance_km: float | None = None


class ChatRequest(BaseModel):
    message: str
    lat: float | None = None
    lng: float | None = None
    conversation_id: str | None = None
    history: list[dict[str, Any]] = Field(default_factory=list)


class ChatRestaurant(BaseModel):
    rid: str
    name: str
    grade: str | None = None
    grade_icon: str | None = None
    distance_km: float | None = None
    distance_label: str | None = None
    reason: str
    detail_path: str
    latitude: float | None = None
    longitude: float | None = None


class CourseSlot(BaseModel):
    label: str
    rid: str
    name: str


class ChatResponse(BaseModel):
    answer: str
    display_answer: str
    restaurants: list[ChatRestaurant]
    course_slots: list[CourseSlot] = Field(default_factory=list)
    retrieval_debug: dict[str, Any]
