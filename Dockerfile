# Dockerfile for MCP Excalidraw Server
# Supports both stdio (local) and SSE (remote/cloud) transport modes
# Set MCP_TRANSPORT=sse for remote access via HTTP

# Stage 1: Build backend (TypeScript compilation)
FROM node:18-slim AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including TypeScript compiler)
RUN npm ci && npm cache clean --force

# Copy backend source
COPY src ./src
COPY tsconfig.json ./

# Compile TypeScript
RUN npm run build:server

# Stage 2: Production MCP Server
FROM node:18-slim AS production

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --gid 1001 nodejs

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy compiled backend (MCP server only)
COPY --from=builder /app/dist ./dist

# Set ownership to nodejs user
RUN chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Set environment variables for SSE mode (cloud deployment)
ENV NODE_ENV=production
ENV MCP_TRANSPORT=sse
ENV MCP_PORT=3001
ENV EXPRESS_SERVER_URL=http://localhost:3000
ENV ENABLE_CANVAS_SYNC=true
ENV EXCALIDRAW_EXPORT_DIR=/tmp

# Expose SSE port
EXPOSE 3001

# Run MCP server
CMD ["node", "dist/index.js"]

# Labels for metadata
LABEL org.opencontainers.image.source="https://github.com/uvirk/mcp_excalidraw"
LABEL org.opencontainers.image.description="MCP Excalidraw Server - SSE transport for remote AI agent access"
LABEL org.opencontainers.image.licenses="MIT"
