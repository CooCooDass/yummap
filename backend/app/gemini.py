from __future__ import annotations

import json
import shutil
import subprocess
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .config import Settings

try:
    from google.auth.transport.requests import Request as GoogleAuthRequest
    from google.oauth2 import service_account
except ImportError:  # pragma: no cover - deployment dependency guard
    GoogleAuthRequest = None
    service_account = None


class GeminiError(RuntimeError):
    pass


class GoogleTokenProvider:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._token: str | None = None
        self._expires_at = 0.0

    def get(self) -> str:
        if self.settings.google_oauth_access_token:
            return self.settings.google_oauth_access_token

        now = time.time()
        if self._token and now < self._expires_at:
            return self._token

        if self.settings.google_service_account_json:
            return self._get_service_account_token(now)

        gcloud_cmd = shutil.which("gcloud") or shutil.which("gcloud.cmd")
        if not gcloud_cmd:
            raise GeminiError(
                "Google auth is not configured. Set GOOGLE_SERVICE_ACCOUNT_JSON "
                "in deployment, or use local gcloud auth for development."
            )

        result = subprocess.run(
            [gcloud_cmd, "auth", "print-access-token"],
            check=True,
            capture_output=True,
            text=True,
        )
        token = result.stdout.strip()
        if not token:
            raise GeminiError("gcloud returned an empty access token")

        self._token = token
        self._expires_at = now + 45 * 60
        return token

    def _get_service_account_token(self, now: float) -> str:
        if GoogleAuthRequest is None or service_account is None:
            raise GeminiError("google-auth is required for GOOGLE_SERVICE_ACCOUNT_JSON")
        try:
            info = json.loads(self.settings.google_service_account_json or "")
        except json.JSONDecodeError as exc:
            raise GeminiError("GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON") from exc

        credentials = service_account.Credentials.from_service_account_info(
            info,
            scopes=["https://www.googleapis.com/auth/cloud-platform"],
        )
        credentials.refresh(GoogleAuthRequest())
        if not credentials.token:
            raise GeminiError("service account token refresh returned an empty token")
        self._token = credentials.token
        expiry = credentials.expiry.timestamp() if credentials.expiry else now + 45 * 60
        self._expires_at = min(expiry - 60, now + 45 * 60)
        return self._token


class GeminiClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.token_provider = GoogleTokenProvider(settings)

    def embed_query(self, query: str) -> list[float] | None:
        if self.settings.disable_gemini:
            return None

        model_id = _normalize_embedding_model(self.settings.embedding_model)
        host = f"aiplatform.{self.settings.google_location}.rep.googleapis.com"
        url = (
            f"https://{host}/v1/projects/{self.settings.google_project_id}/"
            f"locations/{self.settings.google_location}/publishers/google/"
            f"models/{model_id}:embedContent"
        )
        payload = {
            "content": {"parts": [{"text": f"title: none | text: {query}"}]},
            "output_dimensionality": 768,
        }
        data = _post_json(url, payload, self.token_provider.get())
        embedding = data.get("embedding")
        if isinstance(embedding, dict) and isinstance(embedding.get("values"), list):
            return embedding["values"]
        embeddings = data.get("embeddings")
        if isinstance(embeddings, list) and embeddings:
            values = (embeddings[0] or {}).get("values")
            if isinstance(values, list):
                return values
        raise GeminiError(f"unable to parse embedding response: {data}")

    def generate_chat_payload(
        self,
        *,
        message: str,
        candidates: list[dict[str, Any]],
        intent: str,
    ) -> dict[str, Any] | None:
        if self.settings.disable_gemini:
            return None

        prompt = _build_prompt(message=message, candidates=candidates, intent=intent)
        url = (
            "https://aiplatform.googleapis.com/v1/"
            f"projects/{self.settings.google_project_id}/locations/global/"
            f"publishers/google/models/{self.settings.chat_model}:generateContent"
        )
        payload = {
            "systemInstruction": {
                "parts": [
                    {
                        "text": (
                            "너는 원주 식당 추천 어시스턴트다. 반드시 제공된 후보 식당 안에서만 "
                            "추천하고, 후보에 없는 식당/주소/메뉴/영업시간을 지어내지 않는다. "
                            "답변은 한국어로 짧고 구체적으로 작성한다. 출력은 반드시 JSON 객체 하나만 작성한다."
                        )
                    }
                ]
            },
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": 0.4,
                "topP": 0.9,
                "maxOutputTokens": 8192,
                "thinkingConfig": {"thinkingLevel": "LOW"},
                "responseMimeType": "application/json",
            },
        }
        data = _post_json(url, payload, self.token_provider.get(), timeout=60)
        text = _extract_text(data)
        try:
            parsed = json.loads(_strip_json_fence(text))
        except json.JSONDecodeError as exc:
            raise GeminiError(f"unable to parse JSON response: {text[:500]}") from exc
        if not isinstance(parsed, dict):
            raise GeminiError("Gemini structured response was not a JSON object")
        return parsed

    def generate_answer(
        self,
        *,
        message: str,
        candidates: list[dict[str, Any]],
        intent: str,
    ) -> str | None:
        payload = self.generate_chat_payload(
            message=message,
            candidates=candidates,
            intent=intent,
        )
        if not payload:
            return None
        answer = payload.get("answer_intro") or payload.get("answer")
        return answer if isinstance(answer, str) else None


def _post_json(url: str, payload: dict[str, Any], token: str, timeout: int = 30) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise GeminiError(f"HTTP {exc.code}: {detail}") from exc
    except (URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise GeminiError(str(exc)) from exc


def _normalize_embedding_model(model: str) -> str:
    model_id = model.removeprefix("models/")
    if model_id == "gemini-embedding-002":
        return "gemini-embedding-2"
    return model_id


def _extract_text(response_json: dict[str, Any]) -> str:
    candidates_response = response_json.get("candidates") or []
    parts = (
        ((candidates_response[0] or {}).get("content") or {}).get("parts")
        if candidates_response
        else None
    )
    if isinstance(parts, list):
        texts = [part.get("text") for part in parts if isinstance(part, dict) and part.get("text")]
        if texts:
            return "\n".join(texts).strip()
    raise GeminiError(f"unable to parse generateContent response: {response_json}")


def _strip_json_fence(text: str) -> str:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.removeprefix("```json").removeprefix("```").strip()
        stripped = stripped.removesuffix("```").strip()
    return stripped


def _build_prompt(message: str, candidates: list[dict[str, Any]], intent: str) -> str:
    compact_candidates = []
    for item in candidates:
        compact_candidates.append(
            {
                "rid": item.get("rid"),
                "name": item.get("name"),
                "grade": item.get("grade"),
                "distance_km": item.get("distance_km"),
                "categories": item.get("categories") or [],
                "meal_types": item.get("meal_types") or [],
                "recommendation_tags": item.get("recommendation_tags") or [],
                "road_address": item.get("road_address"),
            }
        )
    return (
        f"사용자 질문: {message}\n"
        f"분류된 의도: {intent}\n"
        "후보 식당 JSON:\n"
        f"{json.dumps(compact_candidates, ensure_ascii=False)}\n\n"
        "요청:\n"
        "다음 JSON 스키마만 반환한다:\n"
        '{"answer_intro":"추천 식당명을 자연스럽게 묶은 한 문장",'
        '"restaurant_ids":["후보 rid만"],'
        '"restaurant_reasons":{"rid":"짧은 추천 이유"},'
        '"course_slots":[{"label":"Day 1 점심","rid":"후보 rid"}]}\n'
        "규칙:\n"
        "1. restaurant_ids와 course_slots.rid는 반드시 후보 JSON에 있는 rid만 사용한다.\n"
        "2. answer_intro에는 restaurant_ids에 넣은 식당만 언급한다.\n"
        "3. 일반 추천은 3~8개, 일정형 질문은 5~8개를 고른다.\n"
        "4. gold/silver를 우선하되 질문 관련성과 거리가 더 중요하면 bronze도 포함할 수 있다.\n"
        "5. 일정형 질문이면 course_slots를 Day/시간대별로 채우고, 일반 추천이면 course_slots는 빈 배열로 둔다.\n"
        "6. answer_intro는 번호 목록 없이 '원주에서 ...를 추천합니다.' 형식의 한 문장으로 작성한다.\n"
        "7. 등급, 거리, 링크는 서버가 실제 데이터로 채우므로 answer_intro에는 쓰지 않는다."
    )
