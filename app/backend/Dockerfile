# ---- Backend API image (Phase 2) --------------------------------------------
# Same hardening as the frontend: slim base, non-root user, read-only-FS ready.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# quotes.txt is baked into the image: VPC B has no internet to fetch data.
COPY app.py quotes.txt ./

RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 8080

# --worker-tmp-dir /dev/shm: works with a read-only root filesystem.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --worker-tmp-dir /dev/shm --access-logfile - app:app"]
