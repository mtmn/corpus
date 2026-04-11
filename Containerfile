# docker.io/node:25-slim
FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be as builder

WORKDIR /app

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

# docker.io/node:25-slim
FROM docker.io/library/node@sha256:435f3537a088a01fd208bb629a4b69c28d85deb9a60af8a710cafc3befd6e3be as builder

WORKDIR /app

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
