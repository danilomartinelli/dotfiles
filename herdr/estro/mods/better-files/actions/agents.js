// Handing a file to an agent: one running, a sub-agent under it, or a new one. The file's
// path goes, not its text: the agent reads it, and sees it as it is by then.
import { agents, hc, run, shared, setShared } from "herdr";

const NEW_AGENT = "new:";
const SPAWN = "spawn:";
const COMPOSE = "better-files.compose";
const NOTICE_MS = 5000;

export const agentName = (agent) => agent?.tab_name || agent?.title || agent?.address || "agent";

export const agentMethods = {
  spaceAgents(space) {
    return agents().filter((a) => a.space === space);
  },

  newAgentChoices() {
    return (shared("better-files.new-agents") ?? []).map((a) => ({
      address: `${NEW_AGENT}${a.key}`,
      isNew: true,
      run: a.run,
      tab_name: `new ${a.name}`,
    }));
  },

  // A sub-agent has to be the parent's own kind, so an agent we can't match has none.
  spawnRun(parent) {
    return (
      (shared("better-files.new-agents") ?? []).find((a) => a.key === parent.program?.key)?.run ??
      null
    );
  },

  // Who a choice means. Its address carries the choice, through the box and on to Send.
  agentAt(address) {
    if (address?.startsWith(SPAWN)) {
      const parent = agents().find((a) => a.address === address.slice(SPAWN.length));
      const command = parent && this.spawnRun(parent);
      return command
        ? {
            ...parent,
            address,
            parentAddress: parent.address,
            spawn: true,
            run: command,
            parentName: agentName(parent),
            tab_name: `${agentName(parent)} (spawn)`,
          }
        : null;
    }
    return (
      agents().find((a) => a.address === address) ??
      this.newAgentChoices().find((a) => a.address === address) ??
      null
    );
  },

  // The menu is its own copy of this mod and closes at once, so it leaves the question here
  // for the sidebar to ask.
  askForPrompt(target, address) {
    setShared(COMPOSE, { at: Date.now(), target, address });
  },

  // Whether a box still has someone to send to. A new agent isn't running yet: it stays,
  // even while the list of agents that can be started is still being read.
  composeGone(address) {
    return !address?.startsWith(NEW_AGENT) && !this.agentAt(address);
  },

  // The question is kept in shared state, which outlives the app, so an agent that has
  // gone since is let go of: its box would only offer a Send that can't work.
  syncCompose(cx) {
    if (this.composer && !this.sending && this.composeGone(this.composer.address)) {
      this.closeComposer(cx);
      this.say("That agent is no longer running.", cx);
    }
    const asked = shared(COMPOSE);
    if (!asked || asked.at === this.composeSeen) return;
    this.composeSeen = asked.at;
    if (this.composeGone(asked.address)) {
      setShared(COMPOSE, null);
      return;
    }
    this.composer = asked;
    this.editor.set_value("");
    this.editor.focus();
    cx.notify();
  },

  say(text, cx) {
    this.notice = text;
    cx.timer.after(NOTICE_MS, (cx) => {
      if (this.notice === text) this.notice = null;
      cx.notify();
    });
  },

  closeComposer(cx) {
    this.composer = null;
    if (shared(COMPOSE)) setShared(COMPOSE, null);
    cx.notify();
  },

  // What `hc` is asked to do. No shell sees the message, which can hold anything typed.
  hcArgs(agent, message, target) {
    if (!agent.spawn) return ["send", agent.address, message];
    return [
      "run",
      "--bg",
      "--json",
      "--parent",
      agent.parentAddress,
      ...(target.on ? ["--on", target.on] : []),
      "--cwd",
      target.root,
      ...agent.run,
      message.startsWith("-") ? ` ${message}` : message,
    ];
  },

  sendToAgent(cx) {
    const { target, address } = this.composer ?? {};
    const prompt = this.editor.value().trim();
    const agent = this.agentAt(address);
    if (!agent || !prompt || this.sending) return;
    const message = `${prompt}\n\n${target.dir ? "Folder" : "File"}: ${target.path}`;
    if (agent.isNew) {
      run("tab.new", { folder: target.root, argv: agent.run, task: message });
      this.say(`Started ${agentName(agent)} in a new tab.`, cx);
      this.closeComposer(cx);
      return;
    }
    this.sending = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const result = await hc(this.hcArgs(agent, message, target));
        if (result.code !== 0) throw new Error(result.stderr || "Agent delivery failed.");
        this.say(
          agent.spawn
            ? `Started a sub-agent under ${agent.parentName}.`
            : `Sent to ${agentName(agent)}.`,
          cx,
        );
        this.closeComposer(cx);
      } catch (e) {
        this.error = e.message; // The box stays open, so nothing typed is lost.
      } finally {
        this.sending = false;
        cx.notify();
      }
    });
  },
};
