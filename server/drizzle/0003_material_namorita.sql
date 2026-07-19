ALTER TABLE "media" ADD COLUMN "studios" jsonb DEFAULT '[]'::jsonb;--> statement-breakpoint
ALTER TABLE "media" ADD COLUMN "episodes_list" jsonb DEFAULT '[]'::jsonb;