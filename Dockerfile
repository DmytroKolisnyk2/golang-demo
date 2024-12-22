FROM golang:1.23-alpine

# Step 2: Set the working directory in the container
WORKDIR /app

# Step 3: Copy the Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Step 4: Copy the rest of the application code
COPY . .

EXPOSE 8080