CREATE TABLE "recommendation_feedback" (
	"user_id" uuid NOT NULL,
	"key" text NOT NULL,
	"kind" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recommendation_feedback_user_id_key_pk" PRIMARY KEY("user_id","key")
);
--> statement-breakpoint
CREATE TABLE "recommendation_targets" (
	"source" text NOT NULL,
	"external_id" integer NOT NULL,
	"title" text NOT NULL,
	"year" integer,
	"images" jsonb NOT NULL,
	"format" text,
	"status" text,
	"episodes" integer,
	"average_score" real,
	"vote_count" integer,
	"popularity" real,
	"genres" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"is_adult" boolean DEFAULT false NOT NULL,
	"country_of_origin" text,
	"airing" boolean DEFAULT false NOT NULL,
	"announced" boolean DEFAULT false NOT NULL,
	"release_date" text,
	"root_id" integer NOT NULL,
	"root_title" text NOT NULL,
	"root_year" integer,
	"root_format" text,
	"root_episodes" integer,
	"root_images" jsonb NOT NULL,
	"member_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"world_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"root_checked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"checked_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recommendation_targets_source_external_id_pk" PRIMARY KEY("source","external_id")
);
--> statement-breakpoint
ALTER TABLE "recommendation_edges" ADD COLUMN "rank" integer;--> statement-breakpoint
ALTER TABLE "recommendation_edges" ADD COLUMN "votes" integer;--> statement-breakpoint
ALTER TABLE "recommendation_feedback" ADD CONSTRAINT "recommendation_feedback_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "recommendation_targets_root_idx" ON "recommendation_targets" USING btree ("source","root_id");