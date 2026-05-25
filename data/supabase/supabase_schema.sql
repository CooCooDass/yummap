-- Supabase push-ready schema for yumap.
create extension if not exists postgis;
create extension if not exists vector;

create table if not exists restaurants (
  rid text primary key,
  name text not null,
  road_address text,
  jibun_address text,
  phone text,
  hours jsonb,
  menus jsonb,
  latitude double precision,
  longitude double precision,
  location geography(Point, 4326),
  grade text,
  categories text[],
  meal_types text[],
  recommendation_tags text[],
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists categories (
  name text primary key,
  main_page_index integer,
  query text,
  total_count integer,
  restaurants jsonb
);

create table if not exists restaurant_search_documents (
  rid text primary key references restaurants(rid),
  name text,
  grade text,
  search_document text not null,
  search_document_sha256 text,
  embedding_model text,
  embedding_dimension integer,
  embedding vector(768),
  embedded_at timestamptz,
  updated_at timestamptz default now()
);

-- Populate location after inserting restaurants:
-- update restaurants
-- set location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
-- where longitude is not null and latitude is not null;

create index if not exists restaurants_location_idx on restaurants using gist(location);
create index if not exists restaurants_grade_idx on restaurants(grade);
create index if not exists restaurants_name_idx on restaurants(name);
create index if not exists restaurant_search_documents_grade_idx on restaurant_search_documents(grade);
-- Add a vector index after data load, choosing one of:
-- create index restaurant_search_documents_embedding_hnsw_idx
--   on restaurant_search_documents using hnsw (embedding vector_cosine_ops);
