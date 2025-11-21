FROM denisgolius/zig:0.15.2 AS build

WORKDIR /build
COPY . .

RUN zig build --release=safe 

# move out the sqlite library.
RUN find .zig-cache -name "libsqlite.so" -exec cp {} zig-out/ \;


FROM alpine:3.22.2

RUN wget -O /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate

WORKDIR /app

COPY --from=build /build/zig-out/bin/reqbin /usr/local/bin
COPY --from=build /build/zig-out/libsqlite.so /usr/local/lib

COPY db ./db
COPY docker-entrypoint.sh /

ENV REQBIN_ADDRESS="0.0.0.0"

ENTRYPOINT ["/docker-entrypoint.sh"]
