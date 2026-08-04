FROM kassany/alpine-ziglang:0.16.0 AS build

USER root:root

WORKDIR /app
COPY . .

# workaround for zig 0.16.0 fetch bug.
RUN mkdir -p $HOME/.cache/zig/tmp

RUN zig build --release=safe


FROM alpine:latest

RUN wget -O /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate

WORKDIR /app

COPY --from=build /app/zig-out/bin/reqbin /usr/local/bin

COPY db ./db
COPY docker-entrypoint.sh /

ENV REQBIN_ADDRESS="0.0.0.0"

ENTRYPOINT ["/docker-entrypoint.sh"]
