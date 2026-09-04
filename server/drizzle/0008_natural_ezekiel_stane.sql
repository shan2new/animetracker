CREATE TABLE "announcement_evidence" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"observation_id" uuid NOT NULL,
	"url" text NOT NULL,
	"publisher" text,
	"published_at" text,
	"tier" text DEFAULT 'unknown' NOT NULL,
	"primary" boolean DEFAULT false NOT NULL
);
--> statement-breakpoint
CREATE TABLE "announcement_observations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"franchise_id" uuid NOT NULL,
	"announcement_id" uuid,
	"dedupe_key" text NOT NULL,
	"status" text NOT NULL,
	"next" text NOT NULL,
	"release" text NOT NULL,
	"note" text,
	"observed_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "catalog_links" (
	"franchise_id" uuid NOT NULL,
	"provider" text NOT NULL,
	"media_type" text NOT NULL,
	"external_id" integer,
	"status" text DEFAULT 'matched' NOT NULL,
	"match_method" text DEFAULT 'catalogue' NOT NULL,
	"confidence" real,
	"evidence" jsonb DEFAULT '{}'::jsonb,
	"checked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "catalog_links_franchise_id_provider_pk" PRIMARY KEY("franchise_id","provider")
);
--> statement-breakpoint
CREATE TABLE "recommendation_edges" (
	"franchise_id" uuid NOT NULL,
	"source" text NOT NULL,
	"external_id" integer NOT NULL,
	"target_franchise_id" uuid,
	"score" real,
	"title" text NOT NULL,
	"year" integer,
	"images" jsonb NOT NULL,
	"checked_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recommendation_edges_franchise_id_source_external_id_pk" PRIMARY KEY("franchise_id","source","external_id")
);
--> statement-breakpoint
CREATE TABLE "user_preferences" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"country" text,
	"language" text DEFAULT 'en' NOT NULL,
	"provider_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "watch_availability_snapshots" (
	"franchise_id" uuid NOT NULL,
	"country" text NOT NULL,
	"status" text NOT NULL,
	"providers" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"link" text,
	"checked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	CONSTRAINT "watch_availability_snapshots_franchise_id_country_pk" PRIMARY KEY("franchise_id","country")
);
--> statement-breakpoint
DROP INDEX "media_title_search_idx";--> statement-breakpoint
ALTER TABLE "franchise" ADD COLUMN "artwork" jsonb;--> statement-breakpoint
ALTER TABLE "franchise_member" ADD COLUMN "watch_order" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "franchise_member" ADD COLUMN "relationship" text;--> statement-breakpoint
ALTER TABLE "franchise_member" ADD COLUMN "optional" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "title_native" text;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "synonyms" jsonb DEFAULT '[]'::jsonb;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "artwork" jsonb;--> statement-breakpoint
ALTER TABLE "announcement_evidence" ADD CONSTRAINT "announcement_evidence_observation_id_announcement_observations_id_fk" FOREIGN KEY ("observation_id") REFERENCES "public"."announcement_observations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "announcement_observations" ADD CONSTRAINT "announcement_observations_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "announcement_observations" ADD CONSTRAINT "announcement_observations_announcement_id_announcements_id_fk" FOREIGN KEY ("announcement_id") REFERENCES "public"."announcements"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "catalog_links" ADD CONSTRAINT "catalog_links_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recommendation_edges" ADD CONSTRAINT "recommendation_edges_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recommendation_edges" ADD CONSTRAINT "recommendation_edges_target_franchise_id_franchise_id_fk" FOREIGN KEY ("target_franchise_id") REFERENCES "public"."franchise"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_preferences" ADD CONSTRAINT "user_preferences_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "watch_availability_snapshots" ADD CONSTRAINT "watch_availability_snapshots_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "announcement_evidence_observation_url_uq" ON "announcement_evidence" USING btree ("observation_id","url");--> statement-breakpoint
CREATE INDEX "announcement_evidence_observation_idx" ON "announcement_evidence" USING btree ("observation_id");--> statement-breakpoint
CREATE INDEX "announcement_observations_franchise_idx" ON "announcement_observations" USING btree ("franchise_id","observed_at");--> statement-breakpoint
CREATE UNIQUE INDEX "catalog_links_provider_external_uq" ON "catalog_links" USING btree ("provider","media_type","external_id") WHERE "catalog_links"."status" = 'matched' and "catalog_links"."external_id" is not null;--> statement-breakpoint
CREATE INDEX "catalog_links_external_idx" ON "catalog_links" USING btree ("provider","external_id");--> statement-breakpoint
CREATE INDEX "recommendation_edges_target_idx" ON "recommendation_edges" USING btree ("target_franchise_id");--> statement-breakpoint
CREATE INDEX "watch_availability_country_expiry_idx" ON "watch_availability_snapshots" USING btree ("country","expires_at");--> statement-breakpoint
CREATE INDEX "media_title_search_idx" ON "media" USING gin (to_tsvector('simple', coalesce("title_english", '') || ' ' || coalesce("title_romaji", '') || ' ' || coalesce("title_native", '') || ' ' || coalesce("synonyms"::text, '')));--> statement-breakpoint

-- Preserve the legacy best image while giving new clients an orientation-explicit gallery.
UPDATE "media"
SET "artwork" = jsonb_build_object(
	'portraits', CASE WHEN coalesce("cover", '') <> '' THEN jsonb_build_array(jsonb_build_object(
		'url', "cover", 'source', "source", 'width', null, 'height', null, 'language', null, 'score', null
	)) ELSE '[]'::jsonb END,
	'landscapes', CASE WHEN coalesce("banner", '') <> '' THEN jsonb_build_array(jsonb_build_object(
		'url', "banner", 'source', "source", 'width', null, 'height', null, 'language', null, 'score', null
	)) ELSE '[]'::jsonb END,
	'logos', '[]'::jsonb
)
WHERE "artwork" IS NULL AND (coalesce("cover", '') <> '' OR coalesce("banner", '') <> '');--> statement-breakpoint

UPDATE "franchise"
SET "artwork" = jsonb_build_object(
	'portraits', CASE WHEN coalesce("cover", '') <> '' THEN jsonb_build_array(jsonb_build_object(
		'url', "cover", 'source', "source", 'width', null, 'height', null, 'language', null, 'score', null
	)) ELSE '[]'::jsonb END,
	'landscapes', CASE WHEN coalesce("banner", '') <> '' THEN jsonb_build_array(jsonb_build_object(
		'url', "banner", 'source', "source", 'width', null, 'height', null, 'language', null, 'score', null
	)) ELSE '[]'::jsonb END,
	'logos', '[]'::jsonb
)
WHERE "artwork" IS NULL AND (coalesce("cover", '') <> '' OR coalesce("banner", '') <> '');--> statement-breakpoint

-- One cross-kind chronology. Clearly optional extras remain last and explicitly identified.
WITH ranked AS (
	SELECT fm."media_id",
		row_number() OVER (
			PARTITION BY fm."franchise_id"
			ORDER BY
				CASE WHEN fm."part_kind" IN ('special', 'music') THEN 1 ELSE 0 END,
				m."season_year" ASC NULLS LAST,
				CASE fm."part_kind"
					WHEN 'season' THEN 0 WHEN 'movie' THEN 1 WHEN 'ova' THEN 2
					WHEN 'ona' THEN 3 WHEN 'special' THEN 4 ELSE 5
				END,
				fm."sequence", fm."media_id"
		) AS position
	FROM "franchise_member" fm
	JOIN "media" m ON m."id" = fm."media_id"
)
UPDATE "franchise_member" fm
SET "watch_order" = ranked.position::integer
FROM ranked
WHERE ranked."media_id" = fm."media_id";--> statement-breakpoint

UPDATE "franchise_member" fm
SET "relationship" = COALESCE(
	(
		SELECT mr."relation_type"
		FROM "media_relations" mr
		JOIN "franchise_member" origin ON origin."media_id" = mr."media_id"
		WHERE mr."related_id" = fm."media_id" AND origin."franchise_id" = fm."franchise_id"
		ORDER BY CASE mr."relation_type"
			WHEN 'SEQUEL' THEN 0 WHEN 'PREQUEL' THEN 1 WHEN 'SIDE_STORY' THEN 2 ELSE 3
		END
		LIMIT 1
	),
	CASE
		WHEN fm."part_kind" = 'special' THEN 'SPECIAL'
		WHEN f."source" = 'tmdb' AND fm."part_kind" = 'season' AND fm."sequence" > 1 THEN 'SEQUEL'
		ELSE NULL
	END
),
"optional" = CASE
	WHEN fm."part_kind" IN ('special', 'music') THEN true
	WHEN EXISTS (
		SELECT 1 FROM "media_relations" mr
		WHERE (mr."media_id" = fm."media_id" OR mr."related_id" = fm."media_id")
			AND mr."relation_type" IN ('SIDE_STORY', 'CHARACTER')
	) THEN true
	ELSE false
END
FROM "franchise" f
WHERE f."id" = fm."franchise_id";--> statement-breakpoint

-- Make current catalogue ownership and existing anime→TMDB matches durable and inspectable.
INSERT INTO "catalog_links" (
	"franchise_id", "provider", "media_type", "external_id", "status", "match_method", "confidence", "evidence"
)
SELECT "id", 'tmdb', 'tv', "external_id", 'matched', 'catalogue_owner', 1, '{}'::jsonb
FROM "franchise"
WHERE "source" = 'tmdb' AND "external_id" IS NOT NULL
ON CONFLICT DO NOTHING;--> statement-breakpoint

INSERT INTO "catalog_links" (
	"franchise_id", "provider", "media_type", "external_id", "status", "match_method", "confidence", "evidence"
)
SELECT "id", 'anilist', 'anime', "primary_media_id", 'matched', 'catalogue_owner', 1, '{}'::jsonb
FROM "franchise"
WHERE "source" = 'anilist' AND "primary_media_id" IS NOT NULL
ON CONFLICT DO NOTHING;--> statement-breakpoint

INSERT INTO "catalog_links" (
	"franchise_id", "provider", "media_type", "external_id", "status", "match_method", "confidence", "evidence", "checked_at"
)
SELECT
	"id",
	'tmdb',
	COALESCE("enrichment"->'videoFallback'->>'mediaType', 'tv'),
	("enrichment"->'videoFallback'->>'externalId')::integer,
	'matched',
	'legacy_title_year_animation',
	0.9,
	'{}'::jsonb,
	CASE
		WHEN "enrichment"->'videoFallback'->>'checkedAt' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
			THEN ("enrichment"->'videoFallback'->>'checkedAt')::timestamptz
		ELSE now()
	END
FROM "franchise"
WHERE "source" = 'anilist'
	AND "enrichment"->'videoFallback'->>'status' = 'matched'
	AND "enrichment"->'videoFallback'->>'externalId' ~ '^[0-9]+$'
ON CONFLICT DO NOTHING;--> statement-breakpoint

-- Existing recommendation JSON immediately powers the explainable discovery feed.
INSERT INTO "recommendation_edges" (
	"franchise_id", "source", "external_id", "target_franchise_id", "score", "title", "year", "images", "checked_at"
)
SELECT
	f."id",
	r->>'source',
	(r->>'externalId')::integer,
	NULL,
	CASE WHEN r->>'score' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (r->>'score')::real ELSE NULL END,
	COALESCE(r->>'title', 'Unknown'),
	CASE WHEN r->>'year' ~ '^[0-9]+$' THEN (r->>'year')::integer ELSE NULL END,
	COALESCE(r->'images', jsonb_build_object('portrait', null, 'landscape', null)),
	CASE
		WHEN f."enrichment"->>'checkedAt' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
			THEN (f."enrichment"->>'checkedAt')::timestamptz
		ELSE now()
	END
FROM "franchise" f
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(f."enrichment"->'related', '[]'::jsonb)) r
WHERE r->>'source' IN ('anilist', 'tmdb') AND r->>'externalId' ~ '^[0-9]+$'
ON CONFLICT DO NOTHING;--> statement-breakpoint

WITH resolved AS (
	SELECT
		re."franchise_id", re."source", re."external_id",
		COALESCE(
			CASE WHEN re."source" = 'anilist' THEN (
				SELECT fm."franchise_id" FROM "franchise_member" fm
				WHERE fm."media_id" = re."external_id" AND fm."franchise_id" <> re."franchise_id"
				LIMIT 1
			) END,
			CASE WHEN re."source" = 'tmdb' THEN (
				SELECT f."id" FROM "franchise" f
				WHERE f."source" = 'tmdb' AND f."external_id" = re."external_id" AND f."id" <> re."franchise_id"
				LIMIT 1
			) END,
			CASE WHEN re."source" = 'tmdb' THEN (
				SELECT cl."franchise_id" FROM "catalog_links" cl
				WHERE cl."provider" = 'tmdb' AND cl."status" = 'matched'
					AND cl."external_id" = re."external_id" AND cl."franchise_id" <> re."franchise_id"
				LIMIT 1
			) END
		) AS target
	FROM "recommendation_edges" re
	WHERE re."target_franchise_id" IS NULL
)
UPDATE "recommendation_edges" re
SET "target_franchise_id" = resolved.target
FROM resolved
WHERE re."franchise_id" = resolved."franchise_id"
	AND re."source" = resolved."source"
	AND re."external_id" = resolved."external_id"
	AND resolved.target IS NOT NULL;--> statement-breakpoint

-- Seed the evidence timeline from every fact already visible in `upcoming`.
WITH inserted AS (
	INSERT INTO "announcement_observations" (
		"franchise_id", "announcement_id", "dedupe_key", "status", "next", "release", "note", "observed_at"
	)
	SELECT
		f."id",
		a."id",
		CASE WHEN COALESCE(f."upcoming"->>'next', '') = ''
			THEN '__state__:' || COALESCE(f."upcoming"->>'status', 'unknown')
			ELSE btrim(lower(regexp_replace(f."upcoming"->>'next', '[^a-zA-Z0-9]+', ' ', 'g')))
		END,
		COALESCE(f."upcoming"->>'status', 'unknown'),
		COALESCE(f."upcoming"->>'next', ''),
		COALESCE(f."upcoming"->>'release', 'TBA'),
		f."upcoming"->>'note',
		CASE
			WHEN f."upcoming"->>'checked' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
				THEN (f."upcoming"->>'checked')::timestamptz
			ELSE now()
		END
	FROM "franchise" f
	LEFT JOIN "announcements" a
		ON a."franchise_id" = f."id"
		AND a."dedupe_key" = btrim(lower(regexp_replace(f."upcoming"->>'next', '[^a-zA-Z0-9]+', ' ', 'g')))
	WHERE f."upcoming" IS NOT NULL
	RETURNING "id", "franchise_id"
)
INSERT INTO "announcement_evidence" (
	"observation_id", "url", "publisher", "published_at", "tier", "primary"
)
SELECT
	i."id",
	f."upcoming"->>'source',
	NULL,
	NULL,
	CASE
		WHEN f."upcoming"->>'source' LIKE '%themoviedb.org/%' OR f."upcoming"->>'source' LIKE '%anilist.co/%' THEN 'catalogue'
		ELSE 'unknown'
	END,
	false
FROM inserted i
JOIN "franchise" f ON f."id" = i."franchise_id"
WHERE COALESCE(f."upcoming"->>'source', '') <> ''
ON CONFLICT DO NOTHING;--> statement-breakpoint

UPDATE "franchise"
SET "upcoming" = "upcoming" || jsonb_build_object(
	'evidence', jsonb_build_array(jsonb_build_object(
		'url', "upcoming"->>'source',
		'publisher', null,
		'publishedAt', null,
		'tier', CASE
			WHEN "upcoming"->>'source' LIKE '%themoviedb.org/%' OR "upcoming"->>'source' LIKE '%anilist.co/%' THEN 'catalogue'
			ELSE 'unknown'
		END,
		'primary', false
	))
)
WHERE "upcoming" IS NOT NULL
	AND COALESCE("upcoming"->>'source', '') <> ''
	AND NOT ("upcoming" ? 'evidence');
