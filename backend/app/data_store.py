from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from .config import Settings


RESTAURANT_COLUMNS = (
    "rid,name,road_address,jibun_address,phone,hours,menus,latitude,longitude,"
    "grade,categories,meal_types,recommendation_tags"
)
CATEGORY_ALIASES = {
    "돈까스": "돈카츠",
    "돈까스집": "돈카츠",
    "한식집": "한식",
    "고기집": "고깃집",
}


class DataStoreError(RuntimeError):
    pass


class DataStore:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._restaurants: list[dict[str, Any]] | None = None
        self._restaurants_by_rid: dict[str, dict[str, Any]] | None = None
        self._categories: dict[str, dict[str, Any]] | None = None
        self._search_documents: dict[str, dict[str, Any]] | None = None
        self._embeddings: dict[str, list[float]] | None = None

    @property
    def source(self) -> str:
        return "supabase" if self.settings.has_supabase else "local-json"

    def health(self) -> dict[str, Any]:
        if self.settings.has_supabase:
            restaurants_count = self._supabase_count("restaurants")
            categories_count = self._supabase_count("categories")
            embedded_count = None
        else:
            restaurants_count = len(self._load_restaurants())
            categories_count = len(self._load_categories())
            embedded_count = len(self._load_embeddings())
        return {
            "source": self.source,
            "restaurants": restaurants_count,
            "categories": categories_count,
            "local_embeddings": embedded_count,
            "supabase_configured": self.settings.has_supabase,
        }

    def list_categories(self) -> list[dict[str, Any]]:
        if self.settings.has_supabase:
            try:
                rows = self._supabase_get(
                    "categories",
                    {
                        "select": "name,query,total_count,main_page_index,restaurants",
                        "order": "main_page_index.asc,name.asc",
                    },
                )
                return rows
            except DataStoreError:
                pass

        categories = self._load_categories()
        return [
            {
                "name": name,
                "query": row.get("query"),
                "total_count": row.get("total_count"),
                "main_page_index": row.get("main_page_index"),
                "restaurants": row.get("restaurants") or [],
            }
            for name, row in sorted(
                categories.items(),
                key=lambda item: (item[1].get("main_page_index") or 9999, item[0]),
            )
        ]

    def get_category(self, name: str) -> dict[str, Any] | None:
        name = CATEGORY_ALIASES.get(name.strip().lower(), name)
        for category in self.list_categories():
            if category["name"] == name:
                return category
        lowered = name.lower()
        for category in self.list_categories():
            if lowered in category["name"].lower() or lowered in str(category.get("query") or "").lower():
                return category
        return None

    def list_restaurants(self) -> list[dict[str, Any]]:
        if self.settings.has_supabase:
            try:
                return self._supabase_get(
                    "restaurants",
                    {
                        "select": RESTAURANT_COLUMNS,
                        "order": "name.asc",
                        "limit": "3000",
                    },
                )
            except DataStoreError:
                pass
        return list(self._load_restaurants())

    def get_restaurant(self, rid: str) -> dict[str, Any] | None:
        if self.settings.has_supabase:
            try:
                rows = self._supabase_get(
                    "restaurants",
                    {
                        "select": RESTAURANT_COLUMNS,
                        "rid": f"eq.{rid}",
                        "limit": "1",
                    },
                )
                if rows:
                    return rows[0]
            except DataStoreError:
                pass
        return self._load_restaurants_by_rid().get(rid)

    def get_restaurants_by_rids(self, rids: list[str]) -> list[dict[str, Any]]:
        if not rids:
            return []
        if self.settings.has_supabase:
            try:
                quoted = ",".join(f'"{rid.replace(chr(34), chr(92) + chr(34))}"' for rid in rids)
                rows = self._supabase_get(
                    "restaurants",
                    {
                        "select": RESTAURANT_COLUMNS,
                        "rid": f"in.({quoted})",
                        "limit": str(max(len(rids), 1)),
                    },
                )
                by_rid = {row["rid"]: row for row in rows}
                return [by_rid[rid] for rid in rids if rid in by_rid]
            except DataStoreError:
                pass

        by_rid = self._load_restaurants_by_rid()
        return [by_rid[rid] for rid in rids if rid in by_rid]

    def search_restaurants_by_text(self, query: str, limit: int) -> list[dict[str, Any]]:
        query = query.strip()
        if not query:
            return []

        if self.settings.has_supabase:
            try:
                safe = query.replace("*", "")
                or_filter = (
                    f"(name.ilike.*{safe}*,road_address.ilike.*{safe}*,"
                    f"jibun_address.ilike.*{safe}*)"
                )
                return self._supabase_get(
                    "restaurants",
                    {
                        "select": RESTAURANT_COLUMNS,
                        "or": or_filter,
                        "limit": str(limit),
                    },
                )
            except DataStoreError:
                pass

        lowered = query.lower()
        scored: list[tuple[int, dict[str, Any]]] = []
        for row in self._load_restaurants():
            text_parts = [
                row.get("name"),
                row.get("road_address"),
                row.get("jibun_address"),
                " ".join(row.get("categories") or []),
                " ".join(row.get("meal_types") or []),
                " ".join(row.get("recommendation_tags") or []),
                _menu_text(row.get("menus")),
            ]
            text = " ".join(str(part) for part in text_parts if part).lower()
            if lowered in text:
                name_score = 100 if lowered in str(row.get("name") or "").lower() else 0
                category_score = 40 if lowered in " ".join(row.get("categories") or []).lower() else 0
                scored.append((name_score + category_score + _grade_sort(row.get("grade")), row))
        return [row for _, row in sorted(scored, key=lambda item: item[0], reverse=True)[:limit]]

    def match_documents(
        self,
        query_embedding: list[float] | None,
        query_text: str,
        match_count: int = 60,
    ) -> list[dict[str, Any]]:
        if query_embedding and self.settings.has_supabase:
            try:
                return self._supabase_rpc(
                    "match_restaurant_search_documents",
                    {
                        "query_embedding": query_embedding,
                        "match_count": match_count,
                        "grade_filter": None,
                    },
                )
            except DataStoreError:
                pass

        documents = self._load_search_documents()
        if query_embedding:
            embeddings = self._load_embeddings()
            scored = []
            for rid, embedding in embeddings.items():
                doc = documents.get(rid)
                if not doc:
                    continue
                similarity = _cosine_similarity(query_embedding, embedding)
                scored.append(
                    {
                        "rid": rid,
                        "name": doc.get("name"),
                        "grade": doc.get("grade"),
                        "search_document": doc.get("search_document"),
                        "similarity": similarity,
                    }
                )
            return sorted(scored, key=lambda row: row["similarity"], reverse=True)[:match_count]

        lowered = query_text.lower()
        scored = []
        for rid, doc in documents.items():
            text = f"{doc.get('name', '')} {doc.get('search_document', '')}".lower()
            overlap = _token_overlap_score(lowered, text)
            if overlap > 0:
                scored.append(
                    {
                        "rid": rid,
                        "name": doc.get("name"),
                        "grade": doc.get("grade"),
                        "search_document": doc.get("search_document"),
                        "similarity": min(1.0, 0.45 + overlap / 20),
                    }
                )
        if not scored:
            for row in self.search_restaurants_by_text(query_text, match_count):
                scored.append(
                    {
                        "rid": row["rid"],
                        "name": row.get("name"),
                        "grade": row.get("grade"),
                        "search_document": " ".join(row.get("categories") or []),
                        "similarity": 0.5,
                    }
                )
        return sorted(scored, key=lambda row: row["similarity"], reverse=True)[:match_count]

    def _supabase_get(self, table: str, params: dict[str, str]) -> list[dict[str, Any]]:
        assert self.settings.supabase_rest_url
        query = urlencode(params, safe="(),.*{}\"")
        url = f"{self.settings.supabase_rest_url}/{table}?{query}"
        return self._request_json(url, method="GET")

    def _supabase_rpc(self, function_name: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
        assert self.settings.supabase_rpc_url
        url = f"{self.settings.supabase_rpc_url}/{quote(function_name)}"
        return self._request_json(url, method="POST", payload=payload)

    def _supabase_count(self, table: str) -> int | None:
        if not self.settings.supabase_rest_url or not self.settings.supabase_service_role_key:
            return None
        url = f"{self.settings.supabase_rest_url}/{table}?select=rid"
        if table == "categories":
            url = f"{self.settings.supabase_rest_url}/{table}?select=name"
        request = Request(
            url,
            headers={
                "apikey": self.settings.supabase_service_role_key,
                "Authorization": f"Bearer {self.settings.supabase_service_role_key}",
                "Prefer": "count=exact",
                "Range": "0-0",
            },
            method="GET",
        )
        try:
            with urlopen(request, timeout=20) as response:
                content_range = response.headers.get("Content-Range", "")
        except (HTTPError, URLError, TimeoutError):
            return None
        if "/" not in content_range:
            return None
        total = content_range.rsplit("/", 1)[-1]
        return int(total) if total.isdigit() else None

    def _request_json(
        self,
        url: str,
        *,
        method: str,
        payload: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        if not self.settings.supabase_service_role_key:
            raise DataStoreError("SUPABASE_SERVICE_ROLE_KEY is not configured")
        body = None
        headers = {
            "apikey": self.settings.supabase_service_role_key,
            "Authorization": f"Bearer {self.settings.supabase_service_role_key}",
        }
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = Request(url, data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=30) as response:
                data = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise DataStoreError(f"Supabase HTTP {exc.code}: {detail}") from exc
        except (URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise DataStoreError(str(exc)) from exc
        if not isinstance(data, list):
            raise DataStoreError(f"expected list response from Supabase, got {type(data).__name__}")
        return data

    def _load_restaurants(self) -> list[dict[str, Any]]:
        if self._restaurants is None:
            self._restaurants = _read_json_list(self.settings.local_restaurants_path)
        return self._restaurants

    def _load_restaurants_by_rid(self) -> dict[str, dict[str, Any]]:
        if self._restaurants_by_rid is None:
            self._restaurants_by_rid = {row["rid"]: row for row in self._load_restaurants()}
        return self._restaurants_by_rid

    def _load_categories(self) -> dict[str, dict[str, Any]]:
        if self._categories is None:
            raw = json.loads(self.settings.local_categories_path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                self._categories = raw
            else:
                self._categories = {row["name"]: row for row in raw}
        return self._categories

    def _load_search_documents(self) -> dict[str, dict[str, Any]]:
        if self._search_documents is None:
            rows = _read_json_list(self.settings.local_search_documents_path)
            self._search_documents = {row["rid"]: row for row in rows}
        return self._search_documents

    def _load_embeddings(self) -> dict[str, list[float]]:
        if self._embeddings is None:
            embeddings: dict[str, list[float]] = {}
            path = self.settings.local_embeddings_path
            if path.exists():
                with path.open("r", encoding="utf-8") as handle:
                    for line in handle:
                        if not line.strip():
                            continue
                        row = json.loads(line)
                        if row.get("rid") and isinstance(row.get("embedding"), list):
                            embeddings[row["rid"]] = row["embedding"]
            self._embeddings = embeddings
        return self._embeddings


def _read_json_list(path: Path) -> list[dict[str, Any]]:
    if path.suffix.lower() == ".jsonl":
        rows: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line_no, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise DataStoreError(f"invalid JSONL at {path}:{line_no}") from exc
                if not isinstance(row, dict):
                    raise DataStoreError(f"expected object JSONL row at {path}:{line_no}")
                rows.append(row)
        return rows

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise DataStoreError(f"expected list JSON at {path}")
    return data


def _menu_text(menus: Any) -> str:
    if not menus:
        return ""
    if isinstance(menus, list):
        return " ".join(str(item.get("name") if isinstance(item, dict) else item) for item in menus)
    return str(menus)


def _grade_sort(grade: str | None) -> int:
    return {"gold": 30, "silver": 20, "bronze": 10}.get(str(grade or "").lower(), 0)


def _cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or not left:
        return 0.0
    dot = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(a * a for a in left))
    right_norm = math.sqrt(sum(b * b for b in right))
    if not left_norm or not right_norm:
        return 0.0
    return dot / (left_norm * right_norm)


def _token_overlap_score(query: str, text: str) -> int:
    tokens = _query_tokens(query)
    if not tokens:
        return 0
    return sum(1 for token in tokens if token in text or any(piece in token for piece in text.split()))


def _query_tokens(query: str) -> set[str]:
    tokens: set[str] = set()
    for raw_token in query.replace(",", " ").replace("/", " ").split():
        token = raw_token.strip().lower()
        if len(token) < 2:
            continue
        tokens.add(token)
        for suffix in ("집", "식당", "맛집", "요리"):
            if token.endswith(suffix) and len(token) > len(suffix) + 1:
                tokens.add(token[: -len(suffix)])
    return tokens
