FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY apps/agent ./apps/agent
CMD ["node", "apps/agent/src/server.mjs"]
