import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webDir = join(__dirname, "..");

const WEB_PORT =
  process.env.CMUX_WORKSHOP_WEB_PORT || process.env.WEB_PORT || "13331";
const SERVER_PORT =
  process.env.CMUX_WORKSHOP_SERVER_PORT || process.env.PORT || "11573";

function run(name, cwd, command, args, env) {
  const proc = spawn(command, args, {
    cwd,
    stdio: "pipe",
    env: { ...process.env, ...env },
  });

  proc.stdout.on("data", (data) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      console.log(`[${name}] ${line}`);
    }
  });

  proc.stderr.on("data", (data) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      console.error(`[${name}] ${line}`);
    }
  });

  proc.on("close", (code) => {
    console.log(`[${name}] exited with code ${code}`);
    process.exit(code || 0);
  });

  return proc;
}

const server = run(
  "server",
  join(webDir, "server"),
  "node",
  ["--watch", "index.js"],
  { PORT: SERVER_PORT }
);
const client = run(
  "client",
  join(webDir, "client"),
  "npx",
  ["vite", "--port", WEB_PORT, "--strictPort"],
  {
    CMUX_WORKSHOP_WEB_PORT: WEB_PORT,
    CMUX_WORKSHOP_SERVER_PORT: SERVER_PORT,
  }
);

process.on("SIGINT", () => {
  server.kill();
  client.kill();
  process.exit(0);
});
