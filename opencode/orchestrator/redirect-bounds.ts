/**
 * A writer's shell can point a process that never exits at a file that never
 * stops growing: a dev server looping on an error fills the disk long before
 * anyone reads the log. This rejects that one pair — a non-terminating command
 * whose output reaches an uncapped file — and names the bounded form. It bounds
 * nothing else and is not an operating-system sandbox for shell writes.
 */

type Token =
  { kind: "word"; value: string } | { kind: "operator"; value: string };

/** One simple command with the file sinks its own redirects open. */
type Segment = { program: string; argv: string[]; sinks: string[] };

const redirects = new Set([">", ">>", "&>", "&>>", ">&"]);
const inputs = new Set(["<", "<<<"]);
const pipes = new Set(["|", "|&"]);
const separators = new Set(["&&", "||", ";", "&", "(", ")"]);

/** Descriptor targets and null sinks grow no file. */
const devices = new Set([
  "/dev/null",
  "/dev/stdout",
  "/dev/stderr",
  "/dev/tty",
  "/dev/zero",
]);

/** Programs that run until something interrupts them. */
const streamingPrograms = new Set([
  "nodemon",
  "vite",
  "webpack-dev-server",
  "live-server",
  "http-server",
  "browser-sync",
  "serve",
  "watchexec",
  "watchman",
  "entr",
]);

/** Runner scripts and subcommands with the same lifetime. */
const streamingScripts = new Set(["dev", "serve", "start", "watch", "preview"]);

const runners = new Set([
  "npm",
  "pnpm",
  "yarn",
  "bun",
  "bunx",
  "npx",
  "deno",
  "mise",
  "make",
  "just",
  "task",
  "turbo",
  "cargo",
  "rake",
  "poetry",
  "uv",
]);

const streamingFlags = new Set([
  "--watch",
  "--hot",
  "--hot-reload",
  "--hot-only",
  "--live-reload",
]);

/** Filters that cap what reaches the file; the size stays the caller's choice. */
const capPrograms = new Set(["head", "ghead", "tail", "gtail"]);

const base = (value: string) => value.slice(value.lastIndexOf("/") + 1);

/**
 * Quoting-aware enough to tell an operator from an argument that merely spells
 * one. Unparsed shapes fall through as words, which can only relax the guard.
 */
function tokenize(command: string): Token[] {
  const tokens: Token[] = [];
  let word = "";
  let started = false;
  let heredoc: string | undefined;
  let index = 0;
  const flush = () => {
    if (started) tokens.push({ kind: "word", value: word });
    word = "";
    started = false;
  };
  const push = (value: string, consumed = value.length) => {
    flush();
    tokens.push({ kind: "operator", value });
    index += consumed;
  };
  while (index < command.length) {
    const character = command[index];
    if (character === "\\") {
      word += command[index + 1] ?? "";
      started = true;
      index += 2;
      continue;
    }
    if (character === "'") {
      const end = command.indexOf("'", index + 1);
      word += command.slice(index + 1, end < 0 ? command.length : end);
      started = true;
      index = end < 0 ? command.length : end + 1;
      continue;
    }
    if (character === '"') {
      index++;
      started = true;
      while (index < command.length && command[index] !== '"') {
        if (command[index] === "\\") {
          word += command[index + 1] ?? "";
          index += 2;
          continue;
        }
        word += command[index];
        index++;
      }
      index++;
      continue;
    }
    if (/\s/.test(character)) {
      flush();
      if (character === "\n" && heredoc !== undefined) {
        index = skipHeredocBody(command, index + 1, heredoc);
        heredoc = undefined;
        continue;
      }
      index++;
      continue;
    }
    if (character === "<") {
      if (command.startsWith("<<<", index)) {
        push("<<<");
        continue;
      }
      if (command.startsWith("<<", index)) {
        const opener = command.startsWith("<<-", index) ? 3 : 2;
        flush();
        index += opener;
        ({ delimiter: heredoc, index } = heredocDelimiter(command, index));
        continue;
      }
      push("<");
      continue;
    }
    if (character === ">") {
      // A descriptor prefix belongs to the operator, not to the previous word.
      if (started && /^\d+$/.test(word)) {
        word = "";
        started = false;
      }
      if (command.startsWith(">>", index)) push(">>");
      else if (command.startsWith(">&", index)) push(">&");
      else if (command.startsWith(">|", index)) push(">", 2);
      else push(">");
      continue;
    }
    if (character === "&") {
      if (command.startsWith("&&", index)) push("&&");
      else if (command.startsWith("&>>", index)) push("&>>", 3);
      else if (command.startsWith("&>", index)) push("&>");
      else push("&");
      continue;
    }
    if (character === "|") {
      if (command.startsWith("||", index)) push("||");
      else if (command.startsWith("|&", index)) push("|&");
      else push("|");
      continue;
    }
    if (character === ";" || character === "(" || character === ")") {
      push(character);
      continue;
    }
    word += character;
    started = true;
    index++;
  }
  flush();
  return tokens;
}

function heredocDelimiter(command: string, start: number) {
  let index = start;
  let delimiter = "";
  while (index < command.length && /[ \t]/.test(command[index])) index++;
  while (index < command.length && !/\s/.test(command[index])) {
    const character = command[index];
    if (character === "'" || character === '"') {
      const end = command.indexOf(character, index + 1);
      delimiter += command.slice(index + 1, end < 0 ? command.length : end);
      index = end < 0 ? command.length : end + 1;
      continue;
    }
    if (character === "\\") {
      delimiter += command[index + 1] ?? "";
      index += 2;
      continue;
    }
    delimiter += character;
    index++;
  }
  return { delimiter, index };
}

/** A heredoc body is data; a generated script must not read as a live command. */
function skipHeredocBody(
  command: string,
  start: number,
  delimiter: string,
): number {
  if (!delimiter) return start;
  for (let line = start; line <= command.length;) {
    const end = command.indexOf("\n", line);
    const text = command.slice(line, end < 0 ? command.length : end);
    if (text.trim() === delimiter || end < 0)
      return end < 0 ? command.length : end;
    line = end + 1;
  }
  return command.length;
}

/** Groups segments into pipelines, because a cap only bounds its own pipeline. */
function pipelines(tokens: Token[]): Segment[][] {
  const all: Segment[][] = [];
  let pipeline: Segment[] = [];
  let segment: Segment = { program: "", argv: [], sinks: [] };
  let words: string[] = [];
  const closeSegment = () => {
    // Leading NAME=value assignments precede the program they configure.
    let index = 0;
    while (/^[a-zA-Z_][a-zA-Z0-9_]*=/.test(words[index] ?? "")) index++;
    segment.program = words[index] ?? "";
    segment.argv = words.slice(index + 1);
    if (segment.program || segment.sinks.length) pipeline.push(segment);
    segment = { program: "", argv: [], sinks: [] };
    words = [];
  };
  const closePipeline = () => {
    closeSegment();
    if (pipeline.length) all.push(pipeline);
    pipeline = [];
  };
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    if (token.kind === "word") {
      words.push(token.value);
      continue;
    }
    if (redirects.has(token.value)) {
      const next = tokens[index + 1];
      index++;
      if (next?.kind !== "word") continue;
      // 2>&1 and 1>&- duplicate or close a descriptor; they open no file.
      if (token.value === ">&" && /^\d+-?$/.test(next.value)) continue;
      if (!devices.has(next.value)) segment.sinks.push(next.value);
      continue;
    }
    if (inputs.has(token.value)) {
      index++;
      continue;
    }
    if (pipes.has(token.value)) closeSegment();
    else if (separators.has(token.value)) closePipeline();
  }
  closePipeline();
  return all;
}

function runnerTarget(argv: string[]): string | undefined {
  const positional = argv.filter((value) => !value.startsWith("-"));
  const first = positional[0];
  if (first === undefined) return undefined;
  return ["run", "run-script", "exec", "x"].includes(first)
    ? positional[1]
    : first;
}

const isStreamingScript = (value: string) =>
  streamingScripts.has(value) ||
  /^(dev|watch|serve|start|preview):/.test(value);

/** Names the marker so the rejection points at the command, not at the file. */
function streamingMarker(segment: Segment): string | undefined {
  const program = base(segment.program);
  if (streamingPrograms.has(program)) return program;
  const flag = segment.argv.find((value) => streamingFlags.has(value));
  if (flag) return `${program} ${flag}`;
  if (
    program === "tail" &&
    segment.argv.some((value) => ["-f", "-F", "--follow"].includes(value))
  )
    return "tail -f";
  if (runners.has(program)) {
    const target = runnerTarget(segment.argv);
    if (
      target !== undefined &&
      (isStreamingScript(target) || streamingPrograms.has(base(target)))
    )
      return `${program} ${target}`;
  }
  return undefined;
}

const isCapped = (segment: Segment) =>
  capPrograms.has(base(segment.program)) &&
  segment.argv.some(
    (value) =>
      value === "-c" || /^-c\d/.test(value) || value.startsWith("--bytes"),
  );

/** RLIMIT_FSIZE applies to the whole shell invocation, not to one pipeline. */
const limitsFileSize = (all: Segment[][]) =>
  all.some((pipeline) =>
    pipeline.some(
      (segment) =>
        base(segment.program) === "ulimit" && segment.argv.includes("-f"),
    ),
  );

/**
 * Throws before a writer's shell command executes. Rejects only a pipeline that
 * both runs a non-terminating command and lands in a file with no byte cap.
 */
export function assertBoundedRedirect(command: unknown): void {
  if (typeof command !== "string" || !command) return;
  const all = pipelines(tokenize(command));
  if (limitsFileSize(all)) return;
  for (const pipeline of all) {
    if (pipeline.some(isCapped)) continue;
    const sink = pipeline.flatMap((segment) => segment.sinks)[0];
    if (sink === undefined) continue;
    const marker = pipeline.map(streamingMarker).find(Boolean);
    if (!marker) continue;
    throw new Error(
      `Unbounded log redirect: ${marker} runs until it is interrupted, so an error loop fills the disk with ${sink} before anyone reads it. ` +
        `Cap the bytes in the pipeline, as in "… 2>&1 | ghead -c 20000000 > ${sink}", which stops the process at the cap; use ghead from coreutils, because BSD head rejects size suffixes. ` +
        `Use "tail -c" when only the final output matters, or redirect to /dev/null when the log is not evidence. ` +
        `Keep evidence you intend to preserve inside the owned artifact directory.`,
    );
  }
}
