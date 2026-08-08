FROM alpine:3.20

# bash/curl/jq: required by the dinodex scripts.
# python3/py3-pip: run the Flask/Gunicorn web UI.
# tzdata: sane timestamps in logs.
RUN apk add --no-cache bash curl jq python3 py3-pip tzdata

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY app/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# dinodex_extract.sh is intentionally NOT copied into the image — this
# container only runs the hybrid-chain lookup. dinodex_items.json must be
# supplied externally (volume mount / ConfigMap / baked-in file) at the path
# given by DINODEX_ITEMS_FILE. See k8s/deployment.yaml for one way to do this.
COPY scripts/dinodex_hybrid_chain.sh /scripts/dinodex_hybrid_chain.sh
COPY app/ /app/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /scripts/*.sh /entrypoint.sh \
    && mkdir -p /data \
    && chown -R app:app /app /data /scripts

ENV SCRIPTS_DIR=/scripts \
    DINODEX_ITEMS_FILE=/data/dinodex_items.json \
    DINODEX_MAX_CREATURES=10 \
    DINODEX_SLEEP=0.3 \
    DINODEX_CREATURE_SLEEP=3 \
    PORT=8080 \
    WEB_WORKERS=2

USER app

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
