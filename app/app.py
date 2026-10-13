"""
Minimal Flask app that proves which container served the request.

Shows hostname, private IP and (when running on ECS) the task ID and
Availability Zone, read from the ECS Task Metadata Endpoint v4. Refresh
behind the ALB and you should see the values change as requests are
spread across tasks in both AZs.
"""
import json
import os
import socket
import urllib.request

from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

# ECS injects this env var into every container on Fargate (platform 1.4+).
METADATA_URI = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")

PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{{ app_name }}</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 4rem auto; padding: 0 1rem; }
    table { border-collapse: collapse; width: 100%; }
    td { padding: .5rem; border-bottom: 1px solid #ddd; }
    td:first-child { font-weight: 600; width: 40%; }
  </style>
</head>
<body>
  <h1>Hello from {{ app_name }}</h1>
  <p>This request was served by:</p>
  <table>
    {% for key, value in info.items() %}
    <tr><td>{{ key }}</td><td>{{ value }}</td></tr>
    {% endfor %}
  </table>
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


@app.route("/")
def index():
    return render_template_string(
        PAGE, app_name=os.environ.get("APP_NAME", "Phase 1 App"), info=_container_info()
    )


@app.route("/api/whoami")
def whoami():
    return jsonify(_container_info())


@app.route("/health")
def health():
    # Used by the ALB target group health check. Kept dependency-free on purpose.
    return jsonify(status="ok"), 200
