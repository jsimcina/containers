import json
import os
import subprocess
import threading

from flask import Flask, jsonify, request, send_from_directory

SCRIPTS_DIR = os.environ.get("SCRIPTS_DIR", "/scripts")
# dinodex_extract.sh is not bundled in this image; dinodex_items.json must be
# supplied externally (volume mount / ConfigMap / baked-in file) at this path.
ITEMS_FILE = os.environ.get("DINODEX_ITEMS_FILE", "/data/dinodex_items.json")
MAX_CREATURES = int(os.environ.get("DINODEX_MAX_CREATURES", "10"))
RUN_TIMEOUT = int(os.environ.get("RUN_TIMEOUT_SECONDS", "180"))

app = Flask(__name__, static_folder="static", static_url_path="")
items_lock = threading.Lock()


def load_items():
    with items_lock:
        with open(ITEMS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)


def run_script(args, timeout):
    try:
        proc = subprocess.run(
            ["bash", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", (exc.stderr or "") + "\n[timed out]"


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.get("/api/config")
def config():
    return jsonify({"max_creatures": MAX_CREATURES})


@app.get("/api/creatures")
def creatures():
    try:
        items = load_items()
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        return jsonify({"error": f"creature data unavailable: {exc}"}), 503

    result = sorted(
        ({"uuid": i["uuid"], "name": i["name"]} for i in items),
        key=lambda x: x["name"].lower(),
    )
    return jsonify(result)


@app.post("/api/run")
def run():
    payload = request.get_json(silent=True) or {}
    uuids = payload.get("uuids", [])

    if not isinstance(uuids, list) or not all(isinstance(u, str) for u in uuids):
        return jsonify({"error": "uuids must be an array of strings"}), 400
    if not uuids:
        return jsonify({"error": "select at least one creature"}), 400
    if len(uuids) > MAX_CREATURES:
        return jsonify({"error": f"at most {MAX_CREATURES} creatures are allowed"}), 400

    try:
        valid_uuids = {i["uuid"] for i in load_items()}
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        return jsonify({"error": f"creature data unavailable: {exc}"}), 503

    unknown = [u for u in uuids if u not in valid_uuids]
    if unknown:
        return jsonify({"error": f"unknown uuid(s): {', '.join(unknown)}"}), 400

    args = [
        os.path.join(SCRIPTS_DIR, "dinodex_hybrid_chain.sh"),
        "-f", ITEMS_FILE,
        *uuids,
    ]
    code, out, err = run_script(args, RUN_TIMEOUT)

    data = None
    if out.strip():
        try:
            data = json.loads(out)
        except json.JSONDecodeError:
            data = None

    return jsonify({"ok": code == 0, "data": data, "log": err}), (200 if code == 0 else 502)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
