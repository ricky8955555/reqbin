#!/usr/bin/env python3

import functools
import json
import os
import sqlite3
import sys
from typing import Any

PAGESIZE = 100

eprint = functools.partial(print, file=sys.stderr)


def main() -> None:
    url = os.environ.get("DATABASE_URL")
    if not url:
        return eprint("No database url set. Please set it via DATABASE_URL environment variable.")

    with sqlite3.connect(url) as conn:
        cursor = conn.cursor()
        result = cursor.execute("SELECT COUNT(*) FROM captures")
        count: int = result.fetchone()[0]

        for offset in range(0, count, PAGESIZE):
            result = cursor.execute(
                "SELECT id, body FROM captures LIMIT $limit OFFSET $offset",
                {"limit": PAGESIZE, "offset": offset},
            )
            data: list[tuple[int, str | None]] = result.fetchall()

            for id, raw_body in data:
                if raw_body is None:
                    continue

                try:
                    body: dict[str, Any] = json.loads(raw_body)
                except Exception:
                    continue
                else:
                    updated_body = json.dumps(body, ensure_ascii=False)

                cursor.execute("UPDATE captures SET body = ? WHERE id = ?", (updated_body, id))

            conn.commit()


if __name__ == "__main__":
    main()
