# # --- Stage 1: Build ---
# FROM node:18-alpine AS builder

# WORKDIR /app

# # Copy package files
# COPY /package*.json ./

# # Install dependencies
# RUN npm install

# # Copy frontend source code
# COPY frontend/ .

# # We build with a placeholder. This string will be replaced 
# # by the actual ECS environment variable at container startup.
# # ARG PLACEHOLDER_VITE_API_URL
# ENV VITE_API_URL=PLACEHOLDER_VITE_API_URL
# RUN npm run build

# # --- Stage 2: Runtime (Nginx) ---
# FROM nginx:alpine

# # Set working directory to Nginx html folder
# WORKDIR /usr/share/nginx/html

# # Remove default Nginx static assets
# RUN rm -rf ./*

# # Copy the build output from the builder stage
# COPY --from=builder /app/dist .

# # Copy our custom Nginx configuration files
# # presentation-tier.conf should handle your /api/ proxy logic
# COPY presentation-tier.conf /etc/nginx/conf.d/default.conf

# # Create the entrypoint script to swap placeholders for ECS Env Vars
# RUN echo '#!/bin/sh' > /entrypoint.sh && \
#     echo 'find /usr/share/nginx/html -type f -name "*.js" -exec sed -i "s|PLACEHOLDER_VITE_API_URL|${VITE_API_URL}|g" {} +' >> /entrypoint.sh && \
#     echo 'exec "$@"' >> /entrypoint.sh && \
#     chmod +x /entrypoint.sh

# # Expose port 80 for the web server
# EXPOSE 80

# # Use the entrypoint script to perform the variable injection before starting Nginx
# ENTRYPOINT ["/entrypoint.sh"]
# CMD ["nginx", "-g", "daemon off;"]

# --- Stage 1: Build ---
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . . 

# Set the build-time variable to our placeholder string
ENV VITE_API_URL=VITE_API_URL_PLACEHOLDER
RUN npm run build

# --- Stage 2: Runtime (Nginx) ---
FROM nginx:alpine
WORKDIR /usr/share/nginx/html

# Clean default html
RUN rm -rf ./*

# Copy built assets
COPY --from=builder /app/dist .

# 1. NGINX CONFIG REPLACEMENT:
# Copy your template to the special templates folder. 
# Nginx will automatically process this and put the result in /etc/nginx/conf.d/default.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template

# 2. VITE JS VARIABLE REPLACEMENT:
# Drop our shell script into the entrypoint.d directory. 
# Nginx runs all scripts here automatically before starting.
RUN echo '#!/bin/sh' > /docker-entrypoint.d/40-inject-vite-env.sh && \
    echo 'echo "Injecting Runtime Environment Variables into JS..." ' >> /docker-entrypoint.d/40-inject-vite-env.sh && \
    echo 'find /usr/share/nginx/html -type f -name "*.js" -exec sed -i "s|VITE_API_URL_PLACEHOLDER|${VITE_API_URL}|g" {} +' >> /docker-entrypoint.d/40-inject-vite-env.sh && \
    chmod +x /docker-entrypoint.d/40-inject-vite-env.sh

EXPOSE 80

# We no longer need a custom ENTRYPOINT or CMD. 
# The base nginx:alpine image handles it perfectly now.