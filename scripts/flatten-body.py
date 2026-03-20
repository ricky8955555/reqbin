import sqlite3
import os
import functools
import sys
import json
import urllib.parse
from typing import Any, cast

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

        for page in range(0, count, PAGESIZE):
            offset = page * PAGESIZE
            result = cursor.execute(
                "SELECT id, body FROM captures LIMIT $limit OFFSET $offset",
                {"limit": PAGESIZE, "offset": offset},
            )
            data: list[tuple[int, str | None]] = result.fetchall()

            for id, raw_body in data:
                if raw_body is None:
                    continue

                body: dict[str, Any] = json.loads(raw_body)
                assert len(body) == 1, "item count of body should be 1."

                body_type, body_data = next(iter(body.items()))

                match body_type:
                    case "raw":
                        assert isinstance(body_data, str), "the data of body should be a string."
                        raw_body = body_data
                    case "json":
                        raw_body = json.dumps(body_data)
                    case "form":
                        assert isinstance(body_data, dict), "the data of body should be an object."
                        body_data = cast(dict[str, str], body_data)
                        raw_body = "&".join(
                            f"{key}={urllib.parse.quote(value)}" for key, value in body_data.items()
                        )
                    case _:
                        assert False, "unreachable branch."

                cursor.execute("UPDATE captures SET body = ? WHERE id = ?", (raw_body, id))

            conn.commit()


if __name__ == "__main__":
    main()
