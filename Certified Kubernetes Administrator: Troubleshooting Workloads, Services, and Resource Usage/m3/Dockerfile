FROM golang:1.23 AS build
WORKDIR /src
COPY main.go .
RUN go mod init hits && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /app .

FROM gcr.io/distroless/base-debian12:nonroot
COPY --from=build /app /app
ENTRYPOINT ["/app"]
