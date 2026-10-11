# Path-routing reverse proxy in front of Windmill (see Caddyfile).
FROM caddy:2.11.7-alpine

COPY Caddyfile /etc/caddy/Caddyfile

# Fail the build early if the Caddyfile does not parse.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
