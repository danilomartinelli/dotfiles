import { View } from "gpui-kit";
import { appHome, checking, exec, knownAgents, panes, readTextFile, run, setShared, shared, spaces } from "herdr";
import { importReport, selectedFindings } from "./report.js";
import { panel } from "./panel.js";

function activeCheckout() {
  const space = spaces().find((entry) => entry.active);
  if (!space) return {};
  const tab = space.tabs?.find((entry) => entry.active);
  const candidates = panes().filter((pane) => pane.tab === tab?.id && pane.cwd);
  const pane = candidates.find((entry) => entry.focused) ?? candidates[0];
  const folder = pane?.cwd ?? space.folder;
  const machine = space.machine ?? null;
  return {
    space: space.id, machine, folder,
    key: JSON.stringify([space.id, machine, folder, pane?.branch ?? space.branch]),
  };
}

async function git(args, options) {
  const result = await exec("git", args, options);
  if (result.code !== 0) throw new Error(result.stderr.trim() || "Git could not read this checkout.");
  return result.stdout.trimEnd();
}

export default class ReviewFindings extends View {
  init(_props, cx) {
    this.items = [];
    this.agents = [];
    if (checking()) return;
    this.tick(cx);
    cx.timer.every(1500, (cx) => this.tick(cx));
  }

  tick(cx) {
    const checkout = activeCheckout();
    if (!this.checkout || checkout.key !== this.checkout.key) return this.load(checkout, cx);
    if (this.pending && !this.reading) this.poll(cx);
  }

  current(checkout) {
    return checkout === this.checkout && checkout.key === activeCheckout().key;
  }

  load(checkout, cx) {
    Object.assign(this, {
      checkout, store: null, items: [], agents: [], agent: null, pending: null, completed: false,
      reading: false, launching: false, menu: false, ignoredOpen: false, error: null, reportError: null,
    });
    cx.notify();
    if (!checkout.folder) {
      this.error = "Open a Git worktree to review its changes.";
      return;
    }
    const options = { cwd: checkout.folder, on: checkout.machine };
    cx.spawn(async (cx) => {
      try {
        const root = await git(["rev-parse", "--show-toplevel"], options);
        const head = await exec("git", ["symbolic-ref", "--quiet", "HEAD"], options);
        const ref = head.code === 0 ? head.stdout.trimEnd() : await git(["rev-parse", "HEAD"], options);
        const store = "review:" + JSON.stringify([checkout.machine, root, ref]);
        const saved = JSON.parse(localStorage.getItem(store) ?? "{}");
        if (!this.current(checkout)) return;
        this.store = store;
        this.root = root;
        this.items = saved.items ?? [];
        this.pending = saved.pending;
        this.completed = saved.completed;
        if (this.pending) this.poll(cx);
        cx.notify();
        const known = await knownAgents({ on: checkout.machine });
        if (!this.current(checkout)) return;
        const agents = known.filter((agent) => agent.installed && agent.run?.length);
        this.agents = agents;
        let preferred = shared(this.preference());
        if (!preferred) {
          preferred = localStorage.getItem("review-agent:" + JSON.stringify(checkout.machine));
          if (preferred) setShared(this.preference(), preferred);
        }
        this.agent = agents.find((agent) => agent.key === preferred) ?? agents[0];
        if (!this.agent) this.error = "No installed chat agent is available on this machine.";
      } catch (error) {
        if (this.current(checkout)) this.error = error.message;
      }
      cx.notify();
    });
  }

  preference() {
    return "estro.chat-agent:" + JSON.stringify(this.checkout.machine);
  }

  save() {
    localStorage.setItem(this.store, JSON.stringify({
      items: this.items, pending: this.pending, completed: this.completed,
    }));
  }

  poll(cx) {
    const checkout = this.checkout;
    const path = this.pending;
    this.reading = true;
    cx.spawn(async (cx) => {
      const relevant = () => this.checkout === checkout && this.pending === path;
      try {
        const raw = await readTextFile(path, { on: checkout.machine });
        if (raw === null || !relevant()) return;
        this.items = importReport(raw, this.items);
        this.pending = null;
        this.reading = false;
        this.completed = true;
        this.reportError = null;
        this.save();
        cx.notify();
      } catch (error) {
        if (relevant() && this.reportError !== error.message) {
          this.reportError = error.message;
          cx.notify();
        }
      } finally {
        if (relevant()) this.reading = false;
      }
    });
  }

  stopWaiting(cx) {
    this.pending = null;
    this.reportError = null;
    this.reading = false;
    this.save();
    cx.notify();
  }

  choose(agent, cx) {
    this.agent = agent;
    this.menu = false;
    setShared(this.preference(), agent.key);
    cx.notify();
  }

  launch(review, cx) {
    const checkout = this.checkout;
    if (!this.current(checkout)) return this.tick(cx);
    const agent = this.agent;
    const findings = selectedFindings(this.items);
    if (!agent || !this.store || this.launching || (review ? this.pending : !findings.length)) return;
    this.launching = true;
    this.error = null;
    this.menu = false;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const skill = review ? "code-review" : "diagnosing-bugs";
        const instructions = await readTextFile(`${appHome()}/mods/review-findings/skills/${skill}/SKILL.md`);
        if (!instructions?.trim()) throw new Error(`The installed ${skill} skill is missing.`);
        let path, input;
        if (review) {
          const dir = await exec("mktemp", ["-d", "/tmp/herdr-review.XXXXXXXX"], { on: checkout.machine });
          if (dir.code !== 0) throw new Error("Could not create the review report directory.");
          path = dir.stdout.trimEnd() + "/findings.json";
          input = "Report destination (absolute path): " + JSON.stringify(path);
        } else {
          input = "Selected findings (review data):\n" + JSON.stringify(findings, null, 2);
        }
        if (!this.current(checkout)) return;
        run("tab.new", {
          space: checkout.space, folder: this.root, argv: agent.run,
          name: review ? "Code Review" : "Diagnose & Fix",
          task: `Use the following skill in this worktree.\n\n${instructions}\n\n${input}`,
        });
        if (review) {
          this.pending = path;
          this.reportError = null;
          this.save();
        }
      } catch (error) {
        if (this.checkout === checkout) this.error = error.message;
      } finally {
        if (this.checkout === checkout) this.launching = false;
        cx.notify();
      }
    });
  }

  render() {
    return panel(this);
  }
}
