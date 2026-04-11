-- migrate:up
ALTER TABLE "bins" ADD "subpath" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "captures" ADD "subpath" TEXT DEFAULT NULL;

-- migrate:down
ALTER TABLE "bins" DROP "subpath";
ALTER TABLE "captures" DROP "subpath";
