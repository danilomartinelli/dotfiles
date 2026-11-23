// syntax.js: code as coloured runs, for views that draw their own rows. Herdr's highlighter
// only reaches its Editor, which can't draw a diff or mark a line, so this is a small lexer:
// no grammar, but block comments, template strings and open tags carry from line to line.
// Shared byte for byte between Better Files and Better Changes; a test checks they match.

// Each language's own keywords: a word is a keyword only in the languages that have it, so
// `local` stays plain in TypeScript and `for` stays plain in an env file's comment.
const words = (list) => new Set(list.split(" "));
const JS_KEYWORDS = words(
  "abstract as async await break case catch class const continue debugger declare default delete do else " +
    "enum export extends finally for from function get if implements import in infer instanceof interface is " +
    "keyof let namespace new of override package private protected public readonly return satisfies set " +
    "static super switch this throw try type typeof unique using var void while with yield",
);
const GO_KEYWORDS = words(
  "break case chan const continue default defer else fallthrough for func go goto if import interface map " +
    "package range return select struct switch type var",
);
const RS_KEYWORDS = words(
  "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move " +
    "mut pub ref return self Self static struct super trait type unsafe use where while",
);
const PY_KEYWORDS = words(
  "and as assert async await break case class continue def del elif else except finally for from global if " +
    "import in is lambda match nonlocal not or pass raise return self try while with yield",
);
const RB_KEYWORDS = words(
  "alias and begin break case class def do else elsif end ensure for if in module next not or redo " +
    "require rescue retry return self super then undef unless until when while yield",
);
const SH_KEYWORDS = words(
  "alias break case continue declare do done elif else esac exit export fi for function if in local " +
    "readonly return select set shift source then time typeset unset until while",
);
const LUA_KEYWORDS = words("and break do else elseif end for function goto if in local not or repeat return then until while");
const HS_KEYWORDS = words("case class data deriving do else if import in infix instance let module newtype of then type where");
// C, C++, Java, Kotlin, Swift, C#, PHP, Dart and Scala share most of theirs.
const C_KEYWORDS = words(
  "abstract async auto await break case catch char class const continue data default defer delete do double " +
    "else enum extends extension extern final float for friend fun func goto guard if implements import inline " +
    "int interface internal is let long namespace new object open operator override package private protected " +
    "protocol public record register return sealed short signed sizeof static struct super switch template " +
    "this throw throws try typedef typename union unsigned using val var virtual void volatile when where while yield",
);
const DOCKER_KEYWORDS = words(
  "ADD ARG AS CMD COPY ENTRYPOINT ENV EXPOSE FROM HEALTHCHECK LABEL ONBUILD RUN SHELL STOPSIGNAL USER VOLUME WORKDIR",
);
const MAKE_KEYWORDS = words("define else endef endif export ifdef ifeq ifndef ifneq include override");
const GRAPHQL_KEYWORDS = words(
  "directive enum extend fragment implements input interface mutation on query scalar schema subscription type union",
);
const PROTO_KEYWORDS = words(
  "enum extend import map message oneof option optional package repeated required reserved returns rpc service stream syntax",
);
const PRISMA_KEYWORDS = words("datasource enum generator model type view");
const NONE = new Set();

const C_LIKE = { line: "//", block: ["/*", "*/"] };
const HASH = { line: "#" };
// `regex`: a `/` where a value can start opens a regex literal, so `/\/*$/` opens no comment.
const JS_LIKE = { ...C_LIKE, template: true, regex: true, keywords: JS_KEYWORDS };
const SPECS = {
  js: JS_LIKE,
  ts: JS_LIKE,
  jsx: { ...JS_LIKE, markup: true },
  tsx: { ...JS_LIKE, markup: true },
  vue: { ...JS_LIKE, markup: true, markupComment: true },
  svelte: { ...JS_LIKE, markup: true, markupComment: true },
  astro: { ...JS_LIKE, markup: true, markupComment: true },
  html: { markup: true, markupComment: true, keywords: NONE },
  xml: { markup: true, markupComment: true, keywords: NONE },
  css: { block: ["/*", "*/"], keys: true, keywords: NONE },
  // Go's backtick strings are raw: a backslash in them is just a backslash.
  go: { ...C_LIKE, template: true, rawTemplate: true, keywords: GO_KEYWORDS },
  rs: { ...C_LIKE, charQuotes: true, keywords: RS_KEYWORDS },
  c: { ...C_LIKE, charQuotes: true, keywords: C_KEYWORDS },
  // PHP, Dart and Groovy quote strings with ' as well as ", unlike C's single characters.
  cstr: { ...C_LIKE, keywords: C_KEYWORDS },
  py: { ...HASH, triple: true, keywords: PY_KEYWORDS },
  rb: { ...HASH, keywords: RB_KEYWORDS },
  // In shell a # starts a comment only at the start of a word, so `${#arr[@]}` and `$#` aren't.
  sh: { ...HASH, wordComment: true, keywords: SH_KEYWORDS },
  hash: { ...HASH, keywords: NONE },
  dockerfile: { ...HASH, keywords: DOCKER_KEYWORDS },
  makefile: { ...HASH, keywords: MAKE_KEYWORDS },
  graphql: { ...HASH, triple: true, keywords: GRAPHQL_KEYWORDS },
  proto: { ...C_LIKE, keywords: PROTO_KEYWORDS },
  prisma: { ...C_LIKE, keywords: PRISMA_KEYWORDS },
  sql: { line: "--", block: ["/*", "*/"], anyCase: true },
  lua: { line: "--", keywords: LUA_KEYWORDS },
  hs: { line: "--", keywords: HS_KEYWORDS },
  json: { keys: true, data: true },
  jsonc: { ...C_LIKE, keys: true, keywords: NONE },
  yaml: { ...HASH, keys: true, data: true },
  toml: { ...HASH, keys: true, data: true },
  // An env file: `# notes`, `KEY=value` (or `export KEY=value`), values left as written.
  env: { ...HASH, envKeys: true, data: true },
  md: { markdown: true },
  txt: { plain: true },
};
const ALIASES = {
  mjs: "js", cjs: "js", mts: "ts", cts: "ts", htm: "html", svg: "xml", plist: "xml",
  scss: "jsonc", less: "jsonc", yml: "yaml", markdown: "md", log: "txt", csv: "txt",
  h: "c", cc: "c", cpp: "c", cxx: "c", hh: "c", hpp: "c", hxx: "c", m: "c", mm: "c", java: "c",
  kt: "c", kts: "c", swift: "c", cs: "c", php: "cstr", dart: "cstr", scala: "c", groovy: "cstr", gradle: "cstr",
  bash: "sh", zsh: "sh", fish: "sh", bashrc: "sh", zshrc: "sh", zshenv: "sh", zprofile: "sh", profile: "sh",
  nix: "hash", r: "hash", pl: "hash", ex: "hash", exs: "hash", tf: "hash", conf: "hash", gitignore: "hash",
  dockerignore: "hash", ini: "toml", editorconfig: "toml", npmrc: "toml", mk: "makefile", elm: "hs",
  // JSON with comments, and JSON under other names.
  "code-workspace": "jsonc", "code-snippets": "jsonc", json5: "jsonc", "sublime-settings": "jsonc",
  "sublime-project": "jsonc", webmanifest: "json", ipynb: "json", geojson: "json", har: "json",
  // Config and markup that read as their family.
  properties: "toml", cfg: "toml", service: "toml", desktop: "toml", gitmodules: "toml",
  gitattributes: "hash", ps1: "hash", psm1: "hash", gql: "graphql", mdx: "md",
  csproj: "xml", vbproj: "xml", fsproj: "xml", props: "xml", targets: "xml", xaml: "xml", xsd: "xml", rss: "xml",
};
const SPECIAL_NAMES = {
  Dockerfile: "dockerfile", Containerfile: "dockerfile", Makefile: "makefile", GNUmakefile: "makefile",
  Justfile: "makefile", Gemfile: "rb", Rakefile: "rb", Brewfile: "rb", Vagrantfile: "rb", Podfile: "rb",
  Fastfile: "rb", Procfile: "hash", CODEOWNERS: "hash", ".babelrc": "jsonc", ".eslintrc": "jsonc",
  ".prettierrc": "jsonc", ".swcrc": "jsonc", ".jshintrc": "jsonc", ".nuxtrc": "env", ".npmrc": "toml",
};
// JSON files that are known to allow comments, by name or by folder.
const JSONC_NAME = /^(?:[jt]sconfig(?:[._-].+)?|devcontainer|\.devcontainer|deno|biome|turbo)\.json$/;

// A file with more lines than this is coloured a row at a time, as rows are drawn, instead
// of top to bottom: a comment or string doesn't carry from one line to the next there, but
// a huge file opens at once.
export const WHOLE_FILE_LINES = 5000;

const SQL_KEYWORDS = new Set(
  ("add alter and as asc begin between by case commit create cross delete desc distinct drop else end exists from " +
    "full group having if in index inner insert into is join key left like limit not null offset on or order outer " +
    "primary references returning right rollback select set table then union unique update values view when where with").split(" "),
);
const CONSTANTS = new Set("true false null undefined nil None True False NaN Infinity iota".split(" "));
const TYPES = new Set(
  ("any bigint bool boolean byte char double error f32 f64 float float64 i8 i16 i32 i64 int int32 int64 isize " +
    "never number object rune str string symbol u8 u16 u32 u64 uint unknown usize").split(" "),
);
const HIGHLIGHT_CHARS = 2000;

const NUMBER = /0[xXbBoO][\da-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?/y;
const WORD = /[A-Za-z_$][\w$]*/y;
const ATTRIBUTE = /[@:#.]?[A-Za-z_][\w.:-]*(?=\s*=|\s|\/?>|$)/y;
const TAG = /<\/?[A-Za-z][\w.:-]*/y;
const DECORATOR = /@[A-Za-z_][\w.]*/y;
const REGEX_AFTER = new Set("return typeof case do else in of new delete void throw yield await".split(" "));
const DEFINES = new Set(["def", "fn", "fun", "func", "function"]);
const KEY_LINE = /^(\s*(?:-\s+)?)(["']?[\w.@/-]+["']?)(?=\s*[:=](?:\s|$))/;
const ENV_KEY = /^(\s*(?:export\s+)?)([A-Za-z_][\w.]*)(?=\s*=)/;

// The kind of language a path is written in, by extension or by a well-known name. `.env`
// and `.env.local`, `.env.test`, …, are env files whatever follows the dot.
export function languageOf(path) {
  const parts = String(path ?? "").split("/");
  const name = parts.pop();
  if (SPECIAL_NAMES[name]) return SPECIAL_NAMES[name];
  if (name === ".env" || name.startsWith(".env.")) return "env";
  if (JSONC_NAME.test(name) || (name.endsWith(".json") && parts.at(-1) === ".vscode")) return "jsonc";
  return name.includes(".") ? name.split(".").pop().toLowerCase() : "txt";
}

// A Markdown code fence's language as the lexer's: the names people write (`typescript`,
// `shell`) as well as extensions (`ts`, `sh`). None, or one it doesn't know, stays plain.
const FENCE_NAMES = {
  javascript: "js", node: "js", typescript: "ts", shell: "sh", shellscript: "sh", console: "sh", terminal: "sh",
  zsh: "sh", bash: "sh", python: "py", python3: "py", ruby: "rb", rust: "rs", golang: "go", kotlin: "c",
  java: "c", csharp: "c", "c#": "c", "c++": "c", cpp: "c", docker: "dockerfile", make: "makefile",
  dotenv: "env", markdown: "md", text: "txt", plaintext: "txt", jsonc: "jsonc", json5: "jsonc", yml: "yaml",
};
export function fenceLanguage(word) {
  const name = String(word ?? "").toLowerCase();
  return FENCE_NAMES[name] ?? (name || "txt");
}

// The colour of each kind of run, from the theme, close to One Dark's choices.
export function syntaxColors(t) {
  return {
    keyword: t.ansi5,
    string: t.ansi2,
    comment: t.dim,
    number: t.ansi1,
    constant: t.ansi6,
    function: t.ansi4,
    type: t.ansi3,
    tag: t.ansi1,
    attribute: t.ansi3,
    property: t.ansi1,
  };
}

// A language it doesn't know is left plain: guessing it as code coloured prose.
const specFor = (language) => SPECS[ALIASES[language] ?? language] ?? SPECS.txt;
const closes = (line, at, quote, raw = false) => {
  for (let i = at; i < line.length; i++) {
    if (line[i] === "\\" && !raw) i++;
    else if (line.startsWith(quote, i)) return i + quote.length;
  }
  return -1;
};

// Every line of a file as runs, carrying state from one line to the next.
export function highlightLines(lines, language) {
  let state = null;
  return lines.map((line) => {
    const result = tokenizeLine(line, language, state);
    state = result.state;
    return result.runs;
  });
}

// One line as `{ runs, state }`. `state` is what the line leaves open (a block comment, a
// template string, a tag); pass it with the next line, or null to start fresh.
export function tokenizeLine(line, language, state = null) {
  const spec = specFor(language);
  if (spec.plain) return { runs: [{ text: line, kind: null }], state: null };
  // A very long line stays plain, but whatever was open before it is still open after it.
  if (line.length > HIGHLIGHT_CHARS) return { runs: [{ text: line, kind: null }], state };
  if (spec.markdown) return { runs: markdownRuns(line), state: null };
  const lexer = new Lexer(line, spec, state);
  lexer.run();
  return { runs: lexer.runs.length ? lexer.runs : [{ text: "", kind: null }], state: lexer.state() };
}

function markdownRuns(line) {
  if (/^#{1,6}\s/.test(line)) return [{ text: line, kind: "keyword" }];
  const runs = [];
  let at = 0;
  for (const match of line.matchAll(/`[^`]+`/g)) {
    if (match.index > at) runs.push({ text: line.slice(at, match.index), kind: null });
    runs.push({ text: match[0], kind: "string" });
    at = match.index + match[0].length;
  }
  if (at < line.length || !runs.length) runs.push({ text: line.slice(at), kind: null });
  return runs;
}

class Lexer {
  constructor(line, spec, state) {
    this.line = line;
    this.spec = spec;
    this.open = state?.open ?? null;
    this.inTag = state?.inTag ?? false;
    this.braces = state?.braces ?? 0;
    this.at = 0;
    this.plainFrom = 0;
    this.runs = [];
  }

  state() {
    return this.open || this.inTag ? { open: this.open, inTag: this.inTag, braces: this.braces } : null;
  }

  emit(end, kind) {
    if (this.at > this.plainFrom) this.runs.push({ text: this.line.slice(this.plainFrom, this.at), kind: null });
    this.runs.push({ text: this.line.slice(this.at, end), kind });
    this.at = end;
    this.plainFrom = end;
  }

  flushPlain() {
    if (this.line.length > this.plainFrom)
      this.runs.push({ text: this.line.slice(this.plainFrom), kind: null });
  }

  sticky(pattern) {
    pattern.lastIndex = this.at;
    return pattern.exec(this.line)?.[0] ?? null;
  }

  // Finishes whatever an earlier line left open; false while it's still open at the end.
  continueOpen() {
    const { kind, until } = this.open;
    const end = kind === "comment" ? this.line.indexOf(until, this.at) : closes(this.line, this.at, until, this.open.raw);
    if (end < 0) {
      this.emit(this.line.length, kind);
      return false;
    }
    this.emit(kind === "comment" ? end + until.length : end, kind);
    this.open = null;
    return true;
  }

  run() {
    // A key only starts a line that nothing was left open on: after a comment closes
    // mid-line, the text before it is already drawn.
    const fresh = !this.open && !this.inTag;
    if (this.open && !this.continueOpen()) return;
    if (fresh && this.spec.keys) this.keyAtStart(KEY_LINE);
    else if (fresh && this.spec.envKeys) this.keyAtStart(ENV_KEY);
    while (this.at < this.line.length) {
      if (this.inTag ? this.insideTag() : this.next()) continue;
      this.at++;
    }
    this.flushPlain();
  }

  // `key:` in YAML, `key =` in TOML, a JSON key on its own line, `KEY=` in an env file.
  keyAtStart(pattern) {
    const match = pattern.exec(this.line);
    if (!match) return;
    this.at = match[1].length;
    this.emit(this.at + match[2].length, "property");
  }

  // Inside a tag, `{ … }` is code (a JSX or Svelte expression), so its `=>` doesn't close the tag.
  insideTag() {
    const { line, at } = this;
    if (line[at] === "{") {
      this.braces++;
      this.at++;
      return true;
    }
    if (line[at] === "}" && this.braces) {
      this.braces--;
      this.at++;
      return true;
    }
    if (this.braces) return this.next();
    if (line[at] === ">") {
      this.inTag = false;
      return false;
    }
    if (line.startsWith("/>", at)) {
      this.inTag = false;
      this.braces = 0;
      this.at += 2;
      return true;
    }
    const attribute = this.sticky(ATTRIBUTE);
    if (attribute) {
      this.emit(at + attribute.length, "attribute");
      return true;
    }
    return this.next();
  }

  // One token at the cursor; false when the character there stays plain.
  next() {
    const { line, at, spec } = this;
    const char = line[at];
    const wordStart = at === 0 || /[\s;|&()]/.test(line[at - 1]);
    if (spec.line && line.startsWith(spec.line, at) && !(spec.line === "//" && line[at - 1] === ":") && (!spec.wordComment || wordStart)) {
      this.emit(line.length, "comment");
      return true;
    }
    const comment = spec.block && line.startsWith(spec.block[0], at) ? spec.block
      : spec.markupComment && line.startsWith("<!--", at) ? ["<!--", "-->"] : null;
    if (comment) {
      const end = line.indexOf(comment[1], at + comment[0].length);
      if (end < 0) {
        this.open = { kind: "comment", until: comment[1] };
        this.emit(line.length, "comment");
      } else this.emit(end + comment[1].length, "comment");
      return true;
    }
    if (spec.regex && char === "/") {
      const end = this.regexEnd();
      if (end > 0) {
        this.emit(end, "string");
        return true;
      }
    }
    if (spec.triple && (line.startsWith('"""', at) || line.startsWith("'''", at))) return this.multiline(line.slice(at, at + 3));
    if (char === '"' || (char === "'" && !spec.charQuotes)) return this.quoted(char);
    if (char === "'" && spec.charQuotes) {
      const literal = /'(?:\\.|[^\\'])'/y;
      literal.lastIndex = at;
      if (literal.test(line)) {
        this.emit(literal.lastIndex, "string");
        return true;
      }
      return false;
    }
    if (char === "`") return spec.template ? this.multiline("`") : this.quoted("`");
    if (/\d/.test(char) && !/[\w$]/.test(line[at - 1] ?? "")) {
      const number = this.sticky(NUMBER);
      // In data, digits running into letters are a value like an id or a hash, not a number.
      if (spec.data && /[A-Za-z_]/.test(line[at + number.length] ?? "")) {
        this.at += this.sticky(/[\w-]+/y).length;
        return true;
      }
      this.emit(at + number.length, "number");
      return true;
    }
    if (spec.markup && char === "<" && !/[\w$)\]]/.test(line[at - 1] ?? "")) {
      const tag = this.sticky(TAG);
      if (tag) {
        this.emit(at + tag.length, "tag");
        this.inTag = true;
        return true;
      }
    }
    if (char === "@" && !this.inTag) {
      const decorator = this.sticky(DECORATOR);
      if (decorator) {
        this.emit(at + decorator.length, "function");
        return true;
      }
    }
    const word = /[A-Za-z_$]/.test(char) && !/[\w$]/.test(line[at - 1] ?? "") ? this.sticky(WORD) : null;
    if (!word) return false;
    const kind = this.wordKind(word, at);
    this.lastWord = { word, end: at + word.length };
    if (kind) this.emit(at + word.length, kind);
    else this.at += word.length;
    return true;
  }

  // Where a regex literal starting at the cursor ends, or -1 when this `/` divides. A regex
  // can start where a value can: after an operator, an opening bracket, or a word like return.
  regexEnd() {
    const { line, at } = this;
    let p = at - 1;
    while (p >= 0 && /\s/.test(line[p])) p--;
    if (p >= 0 && !/[(,=:[!&|?{};+\-*%>~^]/.test(line[p])) {
      const word = /[\w$]+$/.exec(line.slice(0, p + 1))?.[0];
      if (!REGEX_AFTER.has(word)) return -1;
    }
    let inClass = false;
    for (let i = at + 1; i < line.length; i++) {
      const c = line[i];
      if (c === "\\") i++;
      else if (c === "[") inClass = true;
      else if (c === "]") inClass = false;
      else if (c === "/" && !inClass) {
        if (i === at + 1) return -1;
        let end = i + 1;
        while (/[a-z]/i.test(line[end] ?? "")) end++;
        return end;
      }
    }
    return -1;
  }

  // A string that must close on this line; an unclosed quote is an apostrophe, left plain.
  quoted(quote) {
    const end = closes(this.line, this.at + 1, quote);
    if (end < 0) return false;
    const key = this.spec.keys && /^\s*:/.test(this.line.slice(end));
    this.emit(end, key ? "property" : "string");
    return true;
  }

  // A string that may run over lines: a template, a raw Go string, a Python docstring.
  multiline(quote) {
    const raw = Boolean(this.spec.rawTemplate && quote === "`");
    const end = closes(this.line, this.at + quote.length, quote, raw);
    if (end < 0) {
      this.open = { kind: "string", until: quote, raw };
      this.emit(this.line.length, "string");
    } else this.emit(end, "string");
    return true;
  }

  wordKind(word, at) {
    const { line, spec } = this;
    if (spec.anyCase) return SQL_KEYWORDS.has(word.toLowerCase()) ? "keyword" : null;
    if (spec.data) return CONSTANTS.has(word) ? "constant" : null;
    const named = this.lastWord && DEFINES.has(this.lastWord.word);
    if (named && /^\s+$/.test(line.slice(this.lastWord.end, at))) return "function";
    const after = line.slice(at + word.length);
    const member = line[at - 1] === "." && line[at - 2] !== ".";
    if (!member && spec.keywords?.has(word)) return "keyword";
    if (CONSTANTS.has(word)) return "constant";
    if (/^\s*(?:\?\.)?\(/.test(after)) return member || !/^[A-Z]/.test(word) ? "function" : "type";
    if (TYPES.has(word) || /^[A-Z][A-Za-z\d]*[a-z][A-Za-z\d]*$/.test(word)) return "type";
    if (word.length > 1 && /^[A-Z][A-Z\d_]*$/.test(word)) return "constant";
    return null;
  }
}
