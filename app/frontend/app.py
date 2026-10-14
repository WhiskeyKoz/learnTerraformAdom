"""
Frontend (Phase 2) - public web page in VPC A.

Shows which frontend task served the page, then calls the backend API in
VPC B (over VPC peering, via its internal ALB) and shows which backend task
answered plus a random quote. If the backend is slow or down, the page still
renders with a "Backend unreachable" box (graceful degradation).
"""
import concurrent.futures
import json
import os
import socket
import time
import urllib.request

from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

# ECS injects this env var into every container on Fargate (platform 1.4+).
METADATA_URI = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")

# Set by Terraform to the internal ALB of VPC B (e.g. http://internal-...elb.amazonaws.com).
BACKEND_URL = os.environ.get("BACKEND_URL", "").rstrip("/")
# Short timeout so a slow/dead backend can never hang the page.
BACKEND_TIMEOUT = float(os.environ.get("BACKEND_TIMEOUT", "2"))

# urlopen's timeout only covers connect/read, NOT the DNS lookup before it
# (measured: ~4 s when the backend host doesn't resolve). Running the call in
# a worker thread lets us enforce one deadline on the whole call, DNS included.
_backend_pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)

PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ app_name }}</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 900px; margin: 2rem auto; padding: 0 1rem; color: #222; }
    h1 { margin-bottom: .25rem; }
    .subtitle { color: #666; margin-top: 0; }
    .boxes { display: flex; flex-wrap: wrap; gap: 1rem; }
    .box { flex: 1 1 300px; border: 1px solid #ccc; border-radius: 8px; padding: 1rem; }
    .box h2 { margin-top: 0; font-size: 1.1rem; }
    .frontend { border-top: 4px solid #2b6cb0; }
    .backend  { border-top: 4px solid #2f855a; }
    .error    { border-top: 4px solid #c53030; background: #fff5f5; }
    table { border-collapse: collapse; width: 100%; }
    td { padding: .35rem; border-bottom: 1px solid #eee; font-size: .95rem; word-break: break-all; }
    td:first-child { font-weight: 600; width: 40%; word-break: normal; }
    .status { margin: 1rem 0; font-weight: 600; }
    .ok { color: #2f855a; }
    .fail { color: #c53030; }
    .quote { border-left: 4px solid #2f855a; background: #f7faf7; padding: 1rem 1.25rem; border-radius: 4px; }
    .quote p { font-size: 1.3rem; margin: 0 0 .5rem; }
    .quote .author { color: #555; text-align: right; }
    button { margin-top: 1rem; padding: .5rem 1rem; font-size: 1rem; cursor: pointer; }
  </style>
</head>
<body>
  <h1>{{ app_name }}</h1>
  <p class="subtitle">Frontend (VPC A) &rarr; VPC peering &rarr; Backend API (VPC B)</p>

  <div class="boxes">
    <div class="box frontend">
      <h2>Frontend (VPC A)</h2>
      <table>
        {% for key, value in frontend.items() %}
        <tr><td>{{ key }}</td><td>{{ value }}</td></tr>
        {% endfor %}
      </table>
    </div>

    {% if backend.ok %}
    <div class="box backend">
      <h2>Backend (VPC B)</h2>
      <table>
        {% for key, value in backend.data.served_by.items() %}
        <tr><td>{{ key }}</td><td>{{ value }}</td></tr>
        {% endfor %}
      </table>
    </div>
    {% else %}
    <div class="box error">
      <h2>Backend unreachable</h2>
      <table>
        <tr><td>Backend URL</td><td>{{ backend_url or "(not set)" }}</td></tr>
        <tr><td>Error</td><td>{{ backend.error }}</td></tr>
      </table>
    </div>
    {% endif %}
  </div>

  {% if backend.ok %}
  <p class="status ok">&#10004; Backend call OK &ndash; {{ backend.elapsed_ms }} ms</p>
  <div class="quote">
    <p>&ldquo;{{ backend.data.quote.text }}&rdquo;</p>
    <div class="author">&ndash; {{ backend.data.quote.author }}</div>
  </div>
  {% else %}
  <p class="status fail">&#10008; Backend call failed after {{ backend.elapsed_ms }} ms &ndash; the frontend still works.</p>
  {% endif %}

  <button onclick="location.reload()">New quote</button>
</body>
</html>
"""


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
        # TaskARN ends in the task ID; AvailabilityZone proves multi-AZ spread.
        info["Task ID"] = task.get("TaskARN", "").split("/")[-1]
        info["Availability Zone"] = task.get("AvailabilityZone", "unknown")
        info["Cluster"] = task.get("Cluster", "").split("/")[-1]

    info["Environment"] = os.environ.get("APP_ENV", "local")
    return info


def _fetch_quote():
    with urllib.request.urlopen(f"{BACKEND_URL}/api/quote", timeout=BACKEND_TIMEOUT) as resp:
        return json.load(resp)


def _call_backend():
    """Fetch a quote from the backend. Never raises - returns ok/error instead."""
    if not BACKEND_URL:
        return {"ok": False, "error": "BACKEND_URL is not set", "elapsed_ms": 0}

    start = time.monotonic()
    try:
        data = _backend_pool.submit(_fetch_quote).result(timeout=BACKEND_TIMEOUT)
        result = {"ok": True, "data": data}
    except concurrent.futures.TimeoutError:
        app.logger.warning("Backend call to %s timed out after %ss", BACKEND_URL, BACKEND_TIMEOUT)
        result = {"ok": False, "error": f"Timeout: no answer within {BACKEND_TIMEOUT:g} s"}
    except Exception as exc:
        app.logger.warning("Backend call to %s failed: %s", BACKEND_URL, exc)
        result = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}

    result["elapsed_ms"] = round((time.monotonic() - start) * 1000)
    return result


@app.route("/")
def index():
    return render_template_string(
        PAGE,
        app_name=os.environ.get("APP_NAME", "Quote App"),
        frontend=_container_info(),
        backend=_call_backend(),
        backend_url=BACKEND_URL,
    )


@app.route("/api/status")
def status():
    # Same data as the page, as JSON - used by tests and the deploy script.
    return jsonify(frontend=_container_info(), backend=_call_backend())


@app.route("/api/whoami")
def whoami():
    return jsonify(_container_info())


@app.route("/health")
def health():
    # ALB health check. Deliberately does NOT call the backend: a backend
    # outage must not make the public ALB kill healthy frontend tasks
    # (that would turn a partial outage into a full one).
    return jsonify(status="ok"), 200
