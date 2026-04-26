import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webDir = join(__dirname, "..");

function run(name, cwd, command, args) {
  const proc = spawn(command, args, {
    cwd,
    stdio: "pipe",
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

const server = run("server", join(webDir, "server"), "node", ["--watch", "index.js"]);
const client = run("client", join(webDir, "client"), "npx", ["vite"]);

process.on("SIGINT", () => {
  server.kill();
  client.kill();
  process.exit(0);
});
