# ---- Build stage: compile the frontend ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# Frontend config is baked in at build time (same pattern as Studio's VITE_* build-args)
ARG VITE_BUILD_NUMBER=local
ENV VITE_BUILD_NUMBER=$VITE_BUILD_NUMBER
RUN npm run build

# ---- Runtime stage: serve via Express ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY server ./server
COPY tsconfig.json ./
EXPOSE 8080
CMD ["npm", "run", "start"]
