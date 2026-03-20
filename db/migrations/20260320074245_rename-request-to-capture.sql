-- migrate:up
ALTER TABLE "requests" RENAME TO "captures";

-- migrate:down
ALTER TABLE "captures" RENAME TO "requests";
