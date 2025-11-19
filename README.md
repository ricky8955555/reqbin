# reqbin

reqbin is a tool to collect requests for inspecting and debugging.

## Quick start

```shell
docker build . -t reqbin
docker run --name reqbin -v $(pwd)/data.db:/app/data.db -p 7280:7280 reqbin:latest
```

Then access the application via http://localhost:7280.

## API Reference

### Bin Management

**Following API is authentication needed if configured.**

- `PUT /bins`: Create or update a bin. Bin model should be represented in JSON format.
- `GET /bins`: Fetch all bins. (Limit and offset can be specified via params `limit` and `offset`, with default values `20` and `0`)
- `GET /bins/:bin`: Inspect a bin.
- `DELETE /bins/:bin`: Remove a bin and all the data it captures.
- `GET /view/:bin`: Fetch all captured data of a bin. (Limit and offset can be specified via params `limit` and `offset`, with default values `20` and `0`)

### Capture

- `ANY /access/:bin`: Any request to this route will be captured into specific bin, then the captured data will be returned to the client.

## Configuration

All configurations can be done by setting the following environment variables.

- `REQBIN_MAX_BODY_SIZE`: Max body size of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_QUERY_COUNT`: Max query count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_HEADER_COUNT`: Max header count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_FORM_COUNT`: Max form count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_DATABASE`: Database path. (Default: `data.db`)
- `REQBIN_ADDRESS`: The address used by the HTTP service. (Default: `127.0.0.1`, Dockerfile Default: `::`)
- `REQBIN_PORT`: The port used by the HTTP service. (Default: `7280`)
- `REQBIN_AUTH`: The auth credential in format `[username]:[password]` used for bin management API authentication. (Default: `null`)
