FROM denisgolius/zig:0.15.2 AS build

RUN apk add --update --no-cache sqlite-dev

WORKDIR /build
COPY . .

RUN zig build --release=safe


FROM alpine:3.22.2

RUN wget -O /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate

RUN apk add --update --no-cache sqlite-libs && \
    ln -s /usr/lib/libsqlite3.so.0 /usr/lib/libsqlite.so

WORKDIR /app

COPY --from=build /build/zig-out/bin/reqbin .
COPY db ./db
COPY docker-entrypoint.sh /

ENV REQBIN_ADDRESS="0.0.0.0"

ENTRYPOINT ["/docker-entrypoint.sh"]
