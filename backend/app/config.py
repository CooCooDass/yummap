from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Settings:
    supabase_url: str | None
    supabase_service_role_key: str | None
    google_project_id: str
    google_location: str
    google_service_account_json: str | None
    google_oauth_access_token: str | None
    embedding_model: str
    chat_model: str
    allowed_origins: list[str]
    disable_gemini: bool
    local_restaurants_path: Path
    local_categories_path: Path
    local_search_documents_path: Path
    local_embeddings_path: Path

    @property
    def has_supabase(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)

    @property
    def supabase_rest_url(self) -> str | None:
        if not self.supabase_url:
            return None
        return f"{self.supabase_url.rstrip('/')}/rest/v1"

    @property
    def supabase_rpc_url(self) -> str | None:
        if not self.supabase_url:
            return None
        return f"{self.supabase_url.rstrip('/')}/rest/v1/rpc"


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def get_settings() -> Settings:
    origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000")
    return Settings(
        supabase_url=os.environ.get("SUPABASE_URL") or "https://aftqqlymsupnogbogmoy.supabase.co",
        supabase_service_role_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY"),
        google_project_id=os.environ.get(
            "GOOGLE_CLOUD_PROJECT",
            "project-68a630b4-e1e1-438a-b8e",
        ),
        google_location=os.environ.get("GOOGLE_CLOUD_LOCATION", "us"),
        google_service_account_json=os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON"),
        google_oauth_access_token=os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN"),
        embedding_model=os.environ.get("GEMINI_EMBEDDING_MODEL", "gemini-embedding-002"),
        chat_model=os.environ.get("GEMINI_CHAT_MODEL", "gemini-3-flash-preview"),
        allowed_origins=[item.strip() for item in origins.split(",") if item.strip()],
        disable_gemini=_env_bool("YUMAP_DISABLE_GEMINI", False),
        local_restaurants_path=ROOT_DIR / "data" / "supabase" / "restaurants.json",
        local_categories_path=ROOT_DIR / "data" / "supabase" / "categories.json",
        local_search_documents_path=ROOT_DIR / "data" / "supabase" / "restaurant_search_documents.jsonl",
        local_embeddings_path=ROOT_DIR / "data" / "supabase" / "restaurant_search_documents.jsonl",
    )
