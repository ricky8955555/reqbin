FROM denisgolius/zig:0.15.2 AS build

RUN apk add --update --no-cache sqlite-dev

WORKDIR /build
COPY . .

RUN zig build --release=safe


FROM alpine:3.22.2

RUN apk add --update --no-cache sqlite-libs
RUN ln -s /usr/lib/libsqlite3.so.0 /usr/lib/libsqlite.so

WORKDIR /app
COPY --from=build /build/zig-out/bin/reqbin .

ENV REQBIN_ADDRESS="::"

ENTRYPOINT ["/app/reqbin"]
