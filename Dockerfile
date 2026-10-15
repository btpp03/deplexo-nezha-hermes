FROM alpine:3.19

# curl+unzip for the runtime fetch, ca-certificates so TLS to GitHub/panel works.
RUN apk add --no-cache curl unzip ca-certificates

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Worker: no port. start.sh is the container CMD.
CMD ["/usr/local/bin/start.sh"]
