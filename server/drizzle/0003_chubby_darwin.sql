ALTER TABLE "franchise" ADD COLUMN "source" text DEFAULT 'anilist' NOT NULL;--> statement-breakpoint
ALTER TABLE "franchise" ADD COLUMN "external_id" integer;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "source" text DEFAULT 'anilist' NOT NULL;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "external_id" integer;--> statement-breakpoint
CREATE UNIQUE INDEX "franchise_source_external_uq" ON "franchise" USING btree ("source","external_id") WHERE "franchise"."source" = 'tmdb';--> statement-breakpoint
CREATE UNIQUE INDEX "media_source_external_uq" ON "media" USING btree ("source","external_id") WHERE "media"."source" = 'tmdb';