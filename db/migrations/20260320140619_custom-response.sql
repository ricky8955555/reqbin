-- migrate:up
ALTER TABLE "bins" ADD "responding" TEXT NOT NULL DEFAULT '{"capture": {}}';

-- migrate:down
ALTER TABLE "bins" DROP "responding";
