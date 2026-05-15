FROM alpine:3.20
RUN apk add --no-cache bash curl jq
WORKDIR /app
COPY . .
RUN chmod +x agent.sh tools/*.sh
ENTRYPOINT ["./agent.sh"]
