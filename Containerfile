# docker.io/node:24-slim
FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    libtinfo5 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY spago.yaml spago.lock ./
COPY src ./src
COPY assets ./assets

RUN npm ci --ignore-scripts && \
    curl -fsSL https://npm.duckdb.org/duckdb/duckdb-v1.4.4-node-v137-linux-x64.tar.gz \
      | tar -xz -C node_modules/duckdb/lib/binding --strip-components=1 && \
    npx spago build --jobs 8 && \
    npx esbuild output/Main/index.js --bundle --platform=node --format=esm --outfile=server.js --external:http --external:https --external:dotenv --external:url --external:duckdb --external:@aws-sdk/client-s3 && \
    npx spago bundle --module Client --outfile client.js --platform browser

FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

COPY --from=builder /app/node_modules/duckdb/lib/binding/duckdb.node \
                    ./node_modules/duckdb/lib/binding/duckdb.node
COPY --from=builder /app/server.js ./
COPY --from=builder /app/client.js ./
COPY --from=builder /app/assets ./assets

RUN mkdir -p /app/data && chown -R node:node /app/data

USER node

ENV PORT=8321
ENV DATABASE_FILE=/app/data/corpus.db
ENV NODE_ENV=production

CMD ["node", "--no-deprecation", "server.js"]
