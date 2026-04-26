import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const WEB_PORT = Number(
  process.env.CMUX_WORKSHOP_WEB_PORT || process.env.WEB_PORT || 13331
);
const SERVER_PORT = Number(
  process.env.CMUX_WORKSHOP_SERVER_PORT || process.env.PORT || 11573
);
const SERVER_TARGET = `http://localhost:${SERVER_PORT}`;

export default defineConfig({
  plugins: [react()],
  server: {
    port: WEB_PORT,
    strictPort: true,
    proxy: {
      "/api": {
        target: SERVER_TARGET,
        configure: (proxy) => {
          proxy.on("error", () => {});
        },
      },
      "/socket.io": {
        target: SERVER_TARGET,
        ws: true,
        configure: (proxy) => {
          proxy.on("error", () => {});
        },
      },
    },
  },
});
