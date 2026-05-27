from __future__ import annotations

from typing import Any

import requests


class PlaceSearchError(RuntimeError):
    pass


def search_kakao_place(api_key: str, query: str) -> dict[str, Any] | None:
    response = requests.get(
        "https://dapi.kakao.com/v2/local/search/keyword.json",
        params={"query": query},
        headers={"Authorization": f"KakaoAK {api_key}"},
        timeout=8,
    )
    if response.status_code != 200:
        raise PlaceSearchError(f"Kakao Local API returned {response.status_code}")

    try:
        payload = response.json()
    except ValueError as exc:
        raise PlaceSearchError("Kakao Local API returned invalid JSON") from exc

    documents = payload.get("documents")
    if not isinstance(documents, list) or not documents:
        return None

    first = documents[0]
    if not isinstance(first, dict):
        return None

    try:
        lat = float(first["y"])
        lng = float(first["x"])
    except (KeyError, TypeError, ValueError):
        return None

    return {
        "lat": lat,
        "lng": lng,
        "name": str(first.get("place_name") or query),
    }
