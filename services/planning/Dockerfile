# ---- Stage 1 : build / install des dépendances ----
FROM python:3.12-slim AS build

WORKDIR /app

# Créer un environnement virtuel
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# ---- Stage 2 : runtime ----
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/binome/devhub-campus"

WORKDIR /app

# Copier le venv et le code
COPY --from=build /opt/venv /opt/venv
COPY --from=build /app/app ./app

ENV PATH="/opt/venv/bin:$PATH"

# Créer un utilisateur non-root
RUN useradd -u 1001 -m -s /bin/bash nonroot
USER nonroot

ENV PORT=8080 \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
