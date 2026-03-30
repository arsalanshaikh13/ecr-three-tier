# --- Stage 1: Build ---
FROM node:16-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files first to leverage Docker layer caching
COPY package*.json ./

# Install dependencies (npm ci is faster/more reliable for builds)
RUN npm ci

# Copy the rest of the application code
COPY . .


# Expose the port your app-tier uses (based on your script's health check)
EXPOSE 3200

# Set environment to production
ENV NODE_ENV=production

# ECS handles the process management. We run the node process directly
# instead of using PM2 to ensure logs flow correctly to CloudWatch.
CMD ["node", "server.js"]