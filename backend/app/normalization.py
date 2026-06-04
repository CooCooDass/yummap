from __future__ import annotations

from copy import deepcopy
from typing import Any


DAYS = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]


def normalize_phone(phone: Any) -> str | None:
    if phone is None:
        return None
    value = str(phone).strip()
    if not value:
        return None
    if value.startswith("07-"):
        return f"05{value}"
    return value


def normalize_hours(hours: Any) -> Any:
    if not isinstance(hours, dict):
        return hours

    weekly = hours.get("weekly")
    if not isinstance(weekly, list):
        return hours

    normalized = deepcopy(hours)
    normalized_weekly = []
    current_day_index = -1
    pending_day_index = 0

    for row in weekly:
        if not isinstance(row, dict):
            normalized_weekly.append(row)
            continue

        item = dict(row)
        date = item.get("date")
        if isinstance(date, str) and date.strip():
            item["date"] = date.strip()
            if item["date"] in DAYS:
                current_day_index = DAYS.index(item["date"])
                pending_day_index = current_day_index + 1
        else:
            if _is_break_time(item.get("hours")) and current_day_index >= 0:
                item["date"] = DAYS[current_day_index]
            else:
                item["date"] = DAYS[pending_day_index % len(DAYS)]
                current_day_index = pending_day_index % len(DAYS)
                pending_day_index += 1

        normalized_weekly.append(item)

    normalized["weekly"] = normalized_weekly
    return normalized


def normalize_restaurant_row(row: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(row)
    normalized["phone"] = normalize_phone(normalized.get("phone"))
    normalized["hours"] = normalize_hours(normalized.get("hours"))
    return normalized


def _is_break_time(value: Any) -> bool:
    return "브레이크" in str(value or "")
