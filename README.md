# reqbin

reqbin is a tool to collect requests for inspecting and debugging.

## Quick start

```shell
touch data.db
docker build . -t reqbin
docker run --name reqbin -v $(pwd)/data.db:/app/data.db -p 7280:7280 reqbin:latest
```

Then access the application via http://localhost:7280.

## API Reference

### Endpoints

#### Bin Management

**Following API is authentication needed if configured.**

- `PUT /`: Create or update a bin. Bin model should be represented in JSON format.
- `GET /`: Fetch all bins. (Limit and offset can be specified via params `limit` and `offset`, with default values `20` and `0`)
- `GET /:bin`: Inspect a bin.
- `DELETE /:bin`: Remove a bin and all the requests it captures.
- `GET /:bin/requests`: Fetch all captured requests of a bin. (Limit and offset can be specified via params `limit` and `offset`, with default values `20` and `0`)
- `DELETE /:bin/requests`: Clear all captured requests of a bin.

#### Capture

- `ANY /:bin/access`: Any request to this route will be captured into specific bin, then the captured data will be returned to the client.

### Models

#### Bin

```jsonc
{
    "id": 1,                // ID of the bin in database
    "name": "foo",          // Bin's name
    "body": true,           // Collect requests' body or not
    "query": true,          // Collect requests' query or not
    "headers": false,       // Collect requests' headers or not
    "ips": [                // Restrict source ip if set, otherwise, the source will not be checked.
        "127.0.0.1"
    ],
    "methods": [            // Restrict requests' methods
        "POST"              // Possible values: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, CONNECT, OTHER
    ],
    "content_type": null    // Specify content type if set, otherwise, the content type will be detected via requests' header (Possible values: raw, json, form) (Note: multipart form is not supported)
},
```

#### Request

```jsonc
{
    "id": 1,                            // ID of the request in database
    "bin": 1,                           // Bin ID the request belongs to
    "method": "POST",                   // Request method
    "remote_addr": "127.0.0.1:23333",   // Client address
    "headers": null,                    // Headers (always null if disabled)
    "query": {},                        // Query params (always null if disabled)
    "body": {                           // Body (null if the function is disabled or the request has no body)
        "raw": "foobar"                 // Body content (Key could be raw/json/form, determined by bin's (if specified) or request's content type)
    },
    "time": 1301965440                  // UTC unix timestamp of the request
}
```

## Configuration

All configurations can be done by setting the following environment variables.

- `REQBIN_MAX_BODY_SIZE`: Max body size of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_QUERY_COUNT`: Max query count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_HEADER_COUNT`: Max header count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_MAX_FORM_COUNT`: Max form count of a request. (Default: `null`, while `http.zig`'s default value is used)
- `REQBIN_DATABASE`: Database path. (Default: `data.db`)
- `REQBIN_ADDRESS`: The address used by the HTTP service. (Default: `127.0.0.1`, Dockerfile Default: `0.0.0.0`)
- `REQBIN_PORT`: The port used by the HTTP service. (Default: `7280`)
- `REQBIN_AUTH`: The auth credential in format `[username]:[password]` used for bin management API authentication. (Default: `null`, while authentication is disabled)
- `REQBIN_TRUSTED_PROXIES`: The trusted proxies in CIDR format seperated by commas `,`, used to retrieve real client ip. (Default: `null`, while no proxy is trusted)
