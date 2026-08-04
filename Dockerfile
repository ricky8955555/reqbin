FROM kassany/ziglang:0.16.0 AS build

WORKDIR /build
COPY . .

RUN ["zig", "build", "--release=safe"]


FROM alpine:latest

RUN wget -O /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate

WORKDIR /app

COPY --from=build /build/zig-out/bin/reqbin /usr/local/bin

COPY db ./db
COPY docker-entrypoint.sh /

ENV REQBIN_ADDRESS="0.0.0.0"

ENTRYPOINT ["/docker-entrypoint.sh"]
