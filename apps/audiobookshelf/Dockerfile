ARG TARGETPLATFORM
ARG VERSION
ARG CHANNEL
ARG TARBALL_URL

### STAGE 0: Build client ###
FROM node:20-alpine AS build
RUN apk update && \
    apk add --no-cache --update \
    curl \
    tar
RUN mkdir -p /app
RUN mkdir -p /client
RUN curl -fsSL "${TARBALL_URL}" | tar xzf - -C /app --strip-components=1
WORKDIR /app/client
RUN npm ci && npm cache clean --force
RUN npm run generate

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
    mkdir -p /app \
	&&\
	mkdir -p /client/dist \
    && \
    mkdir -p /server \
    && \
    curl -fsSL "${TARBALL_URL}" | tar xzf - -C /app --strip-components=1 \
    && \
    chown -R root:root /app \
    && chmod -R 755 /app

COPY --from=build /app/client/dist /client/dist

RUN cp -R /app/server/* /server \
	&& \
	cp  /app/index.js / && cp /app/package* / \
	&& \
	rm -rf /app

RUN npm ci --only=production
RUN apk del make python3 g++

EXPOSE 80

ENTRYPOINT ["tini", "--"]
CMD ["node", "index.js"]

LABEL org.opencontainers.image.source="https://github.com/advplyr/audiobookshelf"
