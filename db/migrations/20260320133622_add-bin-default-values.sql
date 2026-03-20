-- migrate:up
CREATE TABLE new_bins(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  body INTEGER NOT NULL DEFAULT TRUE,
  query INTEGER NOT NULL DEFAULT TRUE,
  header INTEGER NOT NULL DEFAULT TRUE,
  ips TEXT DEFAULT NULL,
  methods TEXT DEFAULT NULL
);

INSERT INTO "new_bins" SELECT * FROM "bins";
DROP TABLE "bins";
ALTER TABLE "new_bins" RENAME TO "bins";

CREATE UNIQUE INDEX idx_bins_name ON bins(name);

-- migrate:down

CREATE TABLE new_bins(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  body INTEGER NOT NULL,
  query INTEGER NOT NULL,
  header INTEGER NOT NULL,
  ips TEXT,
  methods TEXT
);

INSERT INTO "new_bins" SELECT * FROM "bins";
DROP TABLE "bins";
ALTER TABLE "new_bins" RENAME TO "bins";

CREATE UNIQUE INDEX idx_bins_name ON bins(name);
