# docker.io/node:24-slim
FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be as builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    libtinfo5 \
    ca-certificates \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY spago.yaml spago.lock ./
COPY src ./src

RUN npm ci && \
    npx spago build --jobs 8 && \
    npx esbuild output/Main/index.js --bundle --platform=node --format=esm --outfile=server.js --external:http --external:https --external:dotenv --external:url --external:duckdb --external:@aws-sdk/client-s3 && \
    npx spago bundle --module Client --outfile client.js --platform browser

# docker.io/node:25-slim
FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be as builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/server.js ./
COPY --from=builder /app/client.js ./

RUN mkdir -p /app/data && chown -R node:node /app/data

USER node

ENV PORT=8321
ENV DATABASE_FILE=/app/data/scorpus.db
ENV NODE_ENV=production

CMD ["node", "--no-deprecation", "server.js"]
