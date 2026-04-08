#!/usr/bin/env python3

import functools
import json
import os
import sqlite3
import sys
from typing import Any

eprint = functools.partial(print, file=sys.stderr)


def main() -> None:
    url = os.environ.get("DATABASE_URL")
    if not url:
        return eprint("No database url set. Please set it via DATABASE_URL environment variable.")

    with sqlite3.connect(url) as conn:
        cursor = conn.cursor()
        result = cursor.execute(
            "SELECT id, responding FROM bins",
        )
        bins: list[tuple[int, str | None]] = result.fetchall()

        for id, raw in bins:
            if raw is None:
                continue

            responding: dict[str, Any] = json.loads(raw)
            assert len(responding) == 1, "item count of responding should be 1."

            typ, data = next(iter(responding.items()))

            if typ == "static":
                body = data["body"]
                assert isinstance(body, str), "body should be a string."

                data["body"] = body.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}")

                raw = json.dumps({"template": data})
                cursor.execute("UPDATE bins SET responding = ? WHERE id = ?", (raw, id))

        conn.commit()


if __name__ == "__main__":
    main()
