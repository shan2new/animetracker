CREATE TABLE "franchise" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text NOT NULL,
	"primary_media_id" integer,
	"cover" text,
	"banner" text,
	"description" text,
	"genres" jsonb DEFAULT '[]'::jsonb,
	"grouping_source" text DEFAULT 'relations' NOT NULL,
	"grouping_model" text,
	"confidence" real,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "franchise_member" (
	"media_id" integer PRIMARY KEY NOT NULL,
	"franchise_id" uuid NOT NULL,
	"part_kind" text NOT NULL,
	"sequence" integer DEFAULT 0 NOT NULL,
	"label" text,
	"added_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "media" (
	"id" integer PRIMARY KEY NOT NULL,
	"title_romaji" text,
	"title_english" text,
	"format" text,
	"status" text,
	"episodes" integer,
	"cover" text,
	"banner" text,
	"description" text,
	"genres" jsonb DEFAULT '[]'::jsonb,
	"next_airing_episode" jsonb,
	"season_year" integer,
	"season" text,
	"popularity" integer,
	"trending" integer,
	"last_aired_at" bigint,
	"fetched_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "media_relations" (
	"media_id" integer NOT NULL,
	"related_id" integer NOT NULL,
	"relation_type" text NOT NULL,
	CONSTRAINT "media_relations_media_id_related_id_relation_type_pk" PRIMARY KEY("media_id","related_id","relation_type")
);
--> statement-breakpoint
CREATE TABLE "progress" (
	"user_id" uuid NOT NULL,
	"media_id" integer NOT NULL,
	"episodes_watched" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "progress_user_id_media_id_pk" PRIMARY KEY("user_id","media_id")
);
--> statement-breakpoint
CREATE TABLE "subscriptions" (
	"user_id" uuid NOT NULL,
	"franchise_id" uuid NOT NULL,
	"status" text DEFAULT 'planned' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subscriptions_user_id_franchise_id_pk" PRIMARY KEY("user_id","franchise_id")
);
--> statement-breakpoint
CREATE TABLE "sync_state" (
	"key" text PRIMARY KEY NOT NULL,
	"value" jsonb,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"clerk_id" text NOT NULL,
	"email" text,
	"last_opened_at" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_clerk_id_unique" UNIQUE("clerk_id")
);
--> statement-breakpoint
ALTER TABLE "franchise_member" ADD CONSTRAINT "franchise_member_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress" ADD CONSTRAINT "progress_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_franchise_id_franchise_id_fk" FOREIGN KEY ("franchise_id") REFERENCES "public"."franchise"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "franchise_member_franchise_idx" ON "franchise_member" USING btree ("franchise_id");--> statement-breakpoint
CREATE INDEX "media_relations_media_idx" ON "media_relations" USING btree ("media_id");