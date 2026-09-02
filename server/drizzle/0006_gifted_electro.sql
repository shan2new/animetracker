ALTER TABLE "franchise" ADD COLUMN "enrichment" jsonb;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "videos" jsonb DEFAULT '[]'::jsonb;