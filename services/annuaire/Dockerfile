# ---- Stage 1 : build / install des dépendances ----
FROM node:20-alpine AS build

WORKDIR /app

# Copier package.json et installer les dépendances de production
COPY package.json ./
RUN npm install --only=production

# Copier le code source
COPY src/ ./src/

# ---- Stage 2 : image runtime ----
FROM node:20-alpine AS runtime

LABEL org.opencontainers.image.source="https://github.com/binome/devhub-campus"

WORKDIR /app

# Copier depuis le stage build
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src

# Utilisateur non-root (fourni par l'image alpine node)
USER node

ENV PORT=8080 \
    LOG_LEVEL=info \
    NODE_ENV=production

EXPOSE 8080

CMD ["node", "src/index.js"]
