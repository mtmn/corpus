# Justfile for PureScript scrobbler

# Default recipe
default: help

# Show help
help:
    @just --list

# Install dependencies
install:
    npx spago install

# Build the project
build:
    npx spago build

# Bundle to JavaScript
bundle:
    npx spago bundle-app --main Main --to index.js --platform node

# Run the application
run:
    node index.js

# Build and run
dev: build run

# Start fresh installation
setup: install build
    @echo "Setup complete! Run 'just run' to start the server"
    @echo "Then visit: http://localhost:8000"

# Clean build artifacts
clean:
    rm -f index.js
    npx spago clean

# Production build
prod: clean bundle
    @echo "Production build complete!"

# Run tests
test:
    npx spago test
