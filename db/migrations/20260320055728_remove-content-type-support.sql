-- migrate:up
ALTER TABLE "bins" DROP "content_type";

-- migrate:down
ALTER TABLE "bins" ADD "content_type" INTEGER;
