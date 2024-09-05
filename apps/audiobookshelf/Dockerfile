FROM node:20-alpine AS build

ARG TARGETPLATFORM
ARG VERSION
ARG CHANNEL
ARG TARBALL_URL

LABEL org.opencontainers.image.source="https://github.com/advplyr/audiobookshelf"


### STAGE 1: Build server ###
FROM node:20-alpine

ENV NODE_ENV=production

RUN apk update && \
    apk add --no-cache --update \
    curl \
    tzdata \
    ffmpeg \
    make \
    gcompat \
    python3 \
    g++ \
    tini \
    && \
    curl -fsSL "${TARBALL_URL}" \
    | tar xzf - -C /app --strip-components=1  \
    && \
    chown -R root:root /app \
    && chmod -R 755 /app \
    && apk del --purge .build-deps \
    && rm -rf \
        /root/.cache \
        /root/.cargo \
        /tmp/*

WORKDIR /app/client
COPY /app/client /client
RUN npm ci && npm cache clean --force
RUN npm run generate

COPY --from=build /app/client/dist /client/dist
COPY index.js package* /
COPY /app/server /server

RUN npm ci --only=production

RUN apk del make python3 g++

EXPOSE 80

ENTRYPOINT ["tini", "--"]
CMD ["node", "index.js"]
