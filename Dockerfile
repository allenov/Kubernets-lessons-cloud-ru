# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go mod files (if they exist)
COPY hello_app/* ./

# Download dependencies
RUN go mod download || true

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Final stage
FROM alpine:latest

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/server .

# Expose port 8080
EXPOSE 8080

# Run the server
CMD ["./server"]
