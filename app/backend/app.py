"""
Backend API (Phase 2) - runs in the isolated VPC B, JSON only.

Serves a random quote on every call from quotes.txt (packaged in the
image - VPC B has no internet). Every response says which task answered,
so the frontend can show that the request crossed the VPC peering link and
which backend AZ served it.
"""
import json
import os
import random
import socket
import urllib.request

from flask import Flask, jsonify

app = Flask(__name__)

# ECS injects this env var into every container on Fargate (platform 1.4+).
METADATA_URI = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
QUOTES_FILE = os.environ.get(
    "QUOTES_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "quotes.txt")
)


def load_quotes(path):
    """Parse 'text | author' lines; skip blanks and # comments."""
    quotes = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            text, sep, author = line.rpartition("|")
            if not sep or not text.strip():
                raise ValueError(f"Bad line in {path} (expected 'text | author'): {line!r}")
            quotes.append(
                {"id": len(quotes) + 1, "text": text.strip(), "author": author.strip() or "Unknown"}
            )
    if not quotes:
        raise ValueError(f"No quotes found in {path}")
    return quotes


# Loaded once at start-up: a broken quotes file stops the container
# immediately (fail fast) instead of failing on every request.
QUOTES = load_quotes(QUOTES_FILE)


def _ecs_metadata():
    """Return task metadata from ECS, or {} when running locally."""
    if not METADATA_URI:
        return {}
    try:
        with urllib.request.urlopen(f"{METADATA_URI}/task", timeout=1) as resp:
            return json.load(resp)
    except Exception:  # metadata is nice-to-have; never fail the request over it
        return {}


def _container_info():
    hostname = socket.gethostname()
    info = {"Hostname": hostname, "Private IP": socket.gethostbyname(hostname)}

    task = _ecs_metadata()
    if task:
        info["Task ID"] = task.get("TaskARN", "").split("/")[-1]
        info["Availability Zone"] = task.get("AvailabilityZone", "unknown")
        info["Cluster"] = task.get("Cluster", "").split("/")[-1]

    info["Environment"] = os.environ.get("APP_ENV", "local")
    return info


@app.route("/api/quote")
def quote():
    # served_by lets the frontend show the backend box from the SAME call.
    return jsonify(quote=random.choice(QUOTES), served_by=_container_info())


@app.route("/api/whoami")
def whoami():
    return jsonify(_container_info())


@app.route("/health")
def health():
    # Used by the internal ALB target group health check.
    return jsonify(status="ok", quotes_loaded=len(QUOTES)), 200


@app.errorhandler(404)
def not_found(_):
    return jsonify(error="not found"), 404
