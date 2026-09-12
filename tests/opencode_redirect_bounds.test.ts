import { expect, test } from "bun:test";
import { assertBoundedRedirect } from "../opencode/orchestrator/redirect-bounds";

const rejects = (command: string) =>
  expect(() => assertBoundedRedirect(command)).toThrow(
    "Unbounded log redirect",
  );
const accepts = (command: string) =>
  expect(() => assertBoundedRedirect(command)).not.toThrow();

test("non-terminating commands cannot open an uncapped file sink", () => {
  for (const command of [
    "npm run dev > dev.log 2>&1",
    "npm start >> server.log 2>&1",
    "pnpm dev &> out.log",
    "bun dev 2>out.log",
    "yarn run watch >build.log",
    "npx vite > vite.log 2>&1",
    "cargo watch -x test > watch.log 2>&1",
    "nodemon server.js > app.log",
    "./node_modules/.bin/vite > vite.log",
    "NODE_ENV=development npm run dev > dev.log 2>&1",
    "jest --watch > jest.log 2>&1",
    "tail -f /var/log/system.log > copy.log",
    "npm run dev:api > api.log 2>&1",
    "mise run serve > serve.log 2>&1",
  ])
    rejects(command);
});

test("a byte cap, a discarded stream or a descriptor dup is already bounded", () => {
  for (const command of [
    "npm run dev 2>&1 | ghead -c 20000000 > dev.log",
    "npm run dev 2>&1 | head -c 20000000 > dev.log",
    "npm run dev 2>&1 | tail -c 5M > dev.log",
    "npm run dev 2>&1 | ghead --bytes=20M > dev.log",
    "npm run dev > /dev/null 2>&1",
    "npm run dev 2>&1",
    "npm run dev > /dev/stdout",
    "ulimit -f 2097152; npm run dev > dev.log 2>&1",
    "npm run dev",
  ])
    accepts(command);
});

test("terminating commands keep their ordinary redirects", () => {
  for (const command of [
    "npm test > test.log 2>&1",
    "npm install --save-dev serve > install.log 2>&1",
    "npm ci > ci.log 2>&1",
    "git diff > changes.patch",
    "rm -rf build > cleanup.log 2>&1",
    "grep -rf patterns.txt src > matches.log",
    "go run ./cmd/server > run.log 2>&1",
    "bun run build > build.log 2>&1",
    "tail -n 50 app.log > excerpt.log",
    "_scripts/test > results.log 2>&1",
  ])
    accepts(command);
});

test("the sink and the streaming command must share one pipeline", () => {
  accepts("npm run dev > /dev/null 2>&1 & git diff > changes.patch");
  accepts("git log > history.log; npm run dev");
  rejects("git diff > changes.patch && npm run dev > dev.log 2>&1");
});

test("quoting and heredoc bodies do not fabricate or hide a redirect", () => {
  accepts("git commit -m 'npm run dev > dev.log'");
  accepts("echo '> dev.log' > note.txt");
  accepts("cat > run.sh <<'EOF'\nnpm run dev > dev.log 2>&1\nEOF");
  rejects('npm run dev > "dev server.log" 2>&1');
  rejects("npm run dev > dev.log 2>&1\ncat run.sh");
});

test("a missing or non-string command reaches the native tool unchanged", () => {
  for (const command of [undefined, null, 42, "", {}])
    accepts(command as unknown as string);
});
