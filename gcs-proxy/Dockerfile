FROM node:22-alpine as builder

# === Stage 1: Build ===

WORKDIR /app

# Install deps and build
COPY package*.json tsconfig.json ./
RUN npm install
COPY src ./src
RUN npm run build

# === Stage 2: Runtime ===
FROM node:22-alpine

WORKDIR /app

# Copy only production deps
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled code from builder
COPY --from=builder /app/dist ./dist

# Start the server
CMD ["node", "dist/index.js"]
