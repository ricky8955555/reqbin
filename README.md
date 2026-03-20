# reqbin

reqbin is a tool to collect requests for inspecting and debugging.

## Quick start

### Pull or Build Image

You can pull the image directly from ghcr.io:

```shell
docker pull ghcr.io/ricky8955555/reqbin:main
```

Or you can build it by yourself:

```shell
git clone https://github.com/ricky8955555/reqbin.git
docker build . -t reqbin
```

### Start the container

```shell
touch data.db
docker run -d --name reqbin -v $(pwd)/data.db:/app/data.db -p 7280:7280 reqbin
```

Then access the application via http://localhost:7280.

## API Reference

### Endpoints

#### Bin Management

**Following API is authentication needed if configured.**

##### `PUT /api/bins`

> Create or update a bin. Bin model should be represented in JSON format.
> 
> Returns (`Bin`): The created bin.

##### `GET /api/bins`

> Fetch all bins.
> 
> Query (`PageParams`): Page options.
> 
> Returns (`Page[Bin]`): The bins with offset and limit specified via page options.

##### `GET /api/bins/:bin`

> Inspect a bin.
> 
> Returns (`Bin`): The bin to inspect.

##### `DELETE /api/bins/:bin`

> Remove a bin and all the captures.

##### `GET /api/bins/:bin/captures`

> Fetch all captures of a bin.
> 
> Returns (`Page[Capture]`): The captures with offset and limit specified via page options.

##### `DELETE /api/bins/:bin/captures`

> Clear all captured accesses of a bin.

##### `GET /api/bins/:bin/captures/:capture`

> Inspect a capture.
> 
> Returns (`Capture`): The capture to inspect.

##### `DELETE /api/bins/:bin/captures/:capture`

> Remove a capture.

#### Capture

##### `ANY /access/:bin`

> Any access to this route will be captured into specific bin, then the captured data will be returned to the client.
> 
> Returns (`Capture`): The access info captured.

### Params

- `:bin`: Bin name.

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
    "responding": {         // Response settings (refer to `Responding` model)
        "capture": {}
    }
},
```

#### Responding

##### capture

Respond captured info in JSON.

```jsonc
{
    "capture": {}
}
```

##### static

Make static response.

```jsonc
{
    "static": {
        "headers": {  // Headers of response
            "Content-Type": "application/json"
        },
        "body": "{\"foo\": \"bar\"}"
    }
}
```

#### Capture

```jsonc
{
    "id": 1,                            // ID of the capture in database
    "bin": 1,                           // Bin ID the capture belongs to
    "method": "POST",                   // Request method
    "remote_addr": "127.0.0.1:23333",   // Client address
    "headers": null,                    // Headers (always null if disabled)
    "query": {},                        // Query params (always null if disabled)
    "body": "foobar",                   // Body (null if the function is disabled or the capture has no body)
    "time": 1301965440                  // UTC unix timestamp of the capture
}
```

#### Page

```jsonc
{
    "total": 10,    // Total count of data
    "count": 1,     // Count of data in the current page
    "data": [       // Data in the current page
        // ...
    ],
}
```

#### PageParams

```jsonc
{
    "offset": 0,    // Data query offset
    "limit": 20,    // Data query limit
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
