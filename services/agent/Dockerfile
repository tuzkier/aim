FROM node:24-bookworm-slim AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

COPY agent ./agent
COPY tsconfig.json ./tsconfig.json
RUN npm run build

FROM node:24-bookworm-slim AS runtime

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=2000

COPY --from=build /app/package.json /app/package-lock.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/agent ./agent
COPY --from=build /app/tsconfig.json ./tsconfig.json
COPY --from=build /app/.output ./.output
# Eve 暂存用户发来的图片要用构建时准备好的沙箱模板；缺了它，发图会让整段会话直接报错。
COPY --from=build /app/.eve/sandbox-cache ./.eve/sandbox-cache

EXPOSE 2000
CMD ["npm", "run", "start"]
