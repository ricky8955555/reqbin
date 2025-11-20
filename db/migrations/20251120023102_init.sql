-- migrate:up
CREATE TABLE bins(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  body INTEGER NOT NULL,
  query INTEGER NOT NULL,
  header INTEGER NOT NULL,
  ips TEXT,
  methods TEXT
);

CREATE UNIQUE INDEX idx_bins_name ON bins(name);

CREATE TABLE requests(
  id INTEGER PRIMARY KEY,
  bin INTEGER NOT NULL,
  method TEXT NOT NULL,
  remote_addr TEXT NOT NULL,
  headers TEXT,
  query TEXT,
  body TEXT,
  time INTEGER NOT NULL,
  FOREIGN KEY(bin) REFERENCES bins(id) ON DELETE CASCADE
);

CREATE INDEX idx_requests_bin ON requests(bin);

-- migrate:down
DROP TABLE bins;
DROP TABLE requests;
