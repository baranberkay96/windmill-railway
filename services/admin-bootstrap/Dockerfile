# One-shot job that replaces Windmill's default admin password (see bootstrap.sh).
FROM curlimages/curl:8.22.0

COPY bootstrap.sh /bootstrap.sh

ENTRYPOINT ["/bin/sh", "/bootstrap.sh"]
