# ---- Base image -------------------------------------------------------------
# slim = small attack surface and fast pulls from ECR into Fargate.
FROM python:3.12-slim

# Don't write .pyc files; flush logs straight to stdout (-> CloudWatch Logs).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# Install dependencies first so this layer is cached between code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as an unprivileged user (least privilege inside the container too).
# Port 8080 is used because non-root users cannot bind ports < 1024.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 8080

# Gunicorn is a production WSGI server; Flask's built-in server is dev-only.
# --worker-tmp-dir /dev/shm: worker heartbeat files go to in-memory tmpfs, so the
# container works with a read-only root filesystem (set in the ECS task definition).
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --worker-tmp-dir /dev/shm --access-logfile - app:app"]
