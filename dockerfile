FROM alpine:3.15

COPY entrypoint.sh /entrypoint.sh
COPY sharepoint.sh /sharepoint.sh

RUN apk add bash curl jq

ENTRYPOINT ["/entrypoint.sh"]
