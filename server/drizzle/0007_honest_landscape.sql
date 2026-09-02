-- Older writers copied a portrait cover into banner when the catalogue had no landscape asset.
-- Exact URL equality identifies that fallback. Clear it so the explicit images.landscape field is
-- honest; the read model can still choose a real landscape image from another franchise part.
UPDATE "media"
SET "banner" = NULL
WHERE "banner" IS NOT NULL AND "cover" IS NOT NULL AND "banner" = "cover";
--> statement-breakpoint
UPDATE "franchise"
SET "banner" = NULL
WHERE "banner" IS NOT NULL AND "cover" IS NOT NULL AND "banner" = "cover";
