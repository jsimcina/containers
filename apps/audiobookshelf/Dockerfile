### STAGE 0: Build client ###
FROM node:20-alpine AS build
ARG TARGETPLATFORM
ARG VERSION


RUN apk update && \
    apk add --no-cache --update \
    curl \
    tar
RUN mkdir -p /app
RUN mkdir -p /client
RUN curl -fsSL "https://github.com/advplyr/audiobookshelf/archive/refs/tags/v${VERSION}.tar.gz" | tar xzf - -C /app --strip-components=1
WORKDIR /app/client
RUN npm ci && npm cache clean --force
RUN npm run generate

### STAGE 1: Build server ###
ARG TARGETPLATFORM
ARG VERSION

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
    tini

RUN mkdir -p /client/dist \
    && \
    mkdir -p /server

COPY --from=build /app/client/dist /client/dist
COPY --from=build /app/server /server
COPY --from=build /app/index.js /app/package* /

RUN npm ci --only=production
RUN apk del make python3 g++

EXPOSE 80

ENTRYPOINT ["tini", "--"]
CMD ["node", "index.js"]

LABEL org.opencontainers.image.source="https://github.com/advplyr/audiobookshelf"
