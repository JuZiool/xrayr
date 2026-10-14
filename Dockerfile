# Build stage.
# 关键点: 固定在 BUILDPLATFORM (通常是 amd64) 上原生执行，
# 再用 GOOS/GOARCH 交叉编译目标架构。
# 否则 BuildKit 会在每个目标架构的 QEMU 模拟环境里重跑 go test + 编译
# 整个 xray-core，非 amd64 架构要 30 分钟以上。
FROM --platform=$BUILDPLATFORM golang:1.25.3-alpine AS builder
WORKDIR /app
COPY . .
ENV CGO_ENABLED=0
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN go mod download
RUN go test ./...
RUN go run . config check -c release/config/config.minimal.yml
RUN go run . config check -c release/config/config.yml.example
RUN go run . config check -c release/config/config.full.yml
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT#v} \
    go build -v -o XrayR -trimpath -ldflags "-s -w -buildid="

# Release
FROM alpine
RUN apk --update --no-cache add tzdata ca-certificates \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN mkdir /etc/XrayR/
COPY --from=builder /app/XrayR /usr/local/bin

ENTRYPOINT [ "XrayR", "--config", "/etc/XrayR/config.yml"]
