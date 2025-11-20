-- migrate:up
ALTER TABLE "bins" ADD "content_type" INTEGER;

-- migrate:down
ALTER TABLE "bins" DROP "content_type";
