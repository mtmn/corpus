FROM docker.io/node:25-slim AS builder

WORKDIR /app

# Satisfy DL3008 (pin versions) and DL3015 (no-install-recommends)
# Note: Pinning exact apt versions is often brittle in rolling distros, 
# but using --no-install-recommends is a standard best practice.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    libtinfo5 \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY spago.yaml spago.lock ./

RUN npm ci
COPY src ./src

RUN npm run build

FROM docker.io/node:25-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/server.js ./
COPY --from=builder /app/client.js ./

RUN mkdir -p /app/data && chown -R node:node /app/data

USER node

# Default port for scorched scrobbler
ENV PORT=8321
ENV DATABASE_FILE=/app/data/scorpus.db
ENV NODE_ENV=production

EXPOSE 8321

CMD ["node", "--no-deprecation", "server.js"]
