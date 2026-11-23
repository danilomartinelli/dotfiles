// Handing work to the agents: who is on this PR, and what to send them.
import { h_flex } from "gpui-base";
import { agents, panes, hc, knownAgents, run } from "herdr";
import { agentsOnPR, commentMessage, fixCheckMessage, unresolvedMessage } from "../github/model.js";
import { SmallButton, MenuButton } from "../views/ui.js";

const NEW_AGENT = "new:";
const SPAWN = "spawn:";

export const agentName = (agent) => agent?.tab_name || agent?.title || agent?.address || "agent";

export const agentMethods = {
  prAgents() {
    if (!this.pr) return [];
    return agentsOnPR({
      agents: agents(),
      panes: panes(),
      pr: this.pr,
      worktrees: this.currentWorktrees(),
      space: this.sp?.id,
    });
  },

  // Those on the PR first, then the rest of this space, who may well be free.
  agentChoices() {
    const on = this.prAgents();
    const others = agents().filter(
      (a) => a.space === this.sp?.id && !on.some((b) => b.address === a.address),
    );
    return [...on, ...others];
  },

  focusAgent(agent) {
    run("agent.focus", { terminal: agent.address });
  },

  // Installed agents on this space's machine, for starting a new one. Herdr keeps the list
  // cached, so asking on every space change costs little.
  loadNewAgents(sp, cx) {
    const machine = sp?.machine ?? null;
    cx.spawn(async (cx) => {
      try {
        const known = await knownAgents({ on: machine });
        if ((this.sp?.machine ?? null) === machine)
          this.newAgents = known.filter((a) => a.installed);
      } catch {
        this.newAgents = [];
      }
      cx.notify();
    });
  },

  newAgentChoices() {
    return (this.newAgents ?? []).map((a) => ({
      address: `${NEW_AGENT}${a.key}`,
      isNew: true,
      run: a.run,
      tab_name: `new ${a.name}`,
    }));
  },

  // Who a choice means: someone running, or one to start.
  agentAt(address) {
    if (address?.startsWith(SPAWN)) {
      const parent = agents().find((a) => a.address === address.slice(SPAWN.length));
      const command = parent && this.spawnRun(parent);
      return command
        ? {
            ...parent,
            // Its own address, so a prompt box remembers the choice and not just the parent.
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

  // A sub-agent has to be the parent's own kind, so an agent we can't match has none.
  spawnRun(parent) {
    return (this.newAgents ?? []).find((a) => a.key === parent.program?.key)?.run ?? null;
  },

  // Work goes where the checkout is: the one this space is in, else the first there is.
  workFolder() {
    const worktrees = this.currentWorktrees();
    const here = worktrees.find((w) => w.path === this.sp?.folder);
    return (here ?? worktrees[0])?.path ?? this.sp?.folder;
  },

  // What `hc` is asked to do. A sub-agent is started here, not by asking its parent: no
  // shell sees the message, which can hold other people's text, and a busy parent is no wait.
  hcArgs(agent, message) {
    if (!agent.spawn) return ["send", agent.address, message];
    const machine = this.sp?.machine;
    return [
      "run",
      "--bg",
      "--json",
      "--parent",
      agent.parentAddress,
      ...(machine ? ["--on", machine] : []),
      ...(this.workFolder() ? ["--cwd", this.workFolder()] : []),
      ...agent.run,
      // Never read as a flag by the agent's command line.
      message.startsWith("-") ? ` ${message}` : message,
    ];
  },

  // A new agent gets its own tab, in the work's folder, with the message as its first prompt.
  startAgent(agent, message) {
    run("tab.new", {
      space: this.sp?.id,
      folder: this.workFolder(),
      argv: agent.run,
      task: message,
    });
    this.notice = `Started ${agentName(agent)} in a new tab.`;
  },

  // A dropdown of who can take this: agents on the PR first, then the rest of this space,
  // then a new one of each installed kind. `send(agent, cx)` does the work.
  agentButton({ id, label, icon, send }) {
    const running = this.agentChoices();
    const fresh = this.newAgentChoices();
    if (this.mutating || !(running.length + fresh.length))
      return SmallButton({
        id,
        icon,
        label: this.mutating ? label : `${label} (no agent)`,
        disabled: true,
        onClick: () => {},
      });
    const chooser = this.chooser({
      id,
      accessibilityLabel: `${label}: choose an agent`,
      width: 260,
      trigger: MenuButton({ id: `${id}-trigger`, label }),
      choices: [
        ...running.flatMap((a) => [
          { id: a.address, label: agentName(a), detail: a.status },
          ...(this.spawnRun(a) ? [{ id: `${SPAWN}${a.address}`, label: `${agentName(a)} (spawn)` }] : []),
        ]),
        ...fresh.map((a, i) => ({
          id: a.address,
          label: `Start ${agentName(a)}`,
          divided: i === 0 && running.length > 0,
        })),
      ],
      onChoose: (address, cx) => send(this.agentAt(address), cx),
    });
    // A click on the chooser shouldn't also count as a click on the row around it.
    return h_flex()
      .id(`${id}-group`)
      .flex_none()
      .items_center()
      .on_click((_e, cx) => cx.stop_propagation())
      .child(chooser);
  },

  // Delivery goes through `hc`, which reaches a busy agent's session too.
  deliver(agent, message, cx, done) {
    if (!agent || this.mutating) return;
    if (agent.isNew) {
      this.startAgent(agent, message);
      done?.();
      cx.notify();
      return;
    }
    const key = this.spaceKey;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const result = await hc(this.hcArgs(agent, message));
        if (result.code !== 0) throw new Error(result.stderr || "Agent delivery failed");
        if (key === this.spaceKey) {
          this.notice = agent.spawn
            ? `Started a sub-agent under ${agent.parentName}.`
            : `Sent to ${agentName(agent)}.`;
          done?.();
        }
      } catch (e) {
        if (key === this.spaceKey) this.error = e.message;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },

  fixCheck(check, agent, cx) {
    this.deliver(agent, fixCheckMessage(this.pr, this.pr.repository, check), cx);
  },

  sendUnresolved(agent, cx) {
    this.deliver(agent, unresolvedMessage(this.pr), cx);
  },

  sendAgent(cx) {
    const composer = this.composer;
    const agent = this.agentAt(this.target);
    const draft = this.draftKey;
    const message = commentMessage(this.pr, this.pr.repository, composer, this.editor.value());
    this.deliver(agent, message, cx, () => {
      if (this.composer !== composer) return;
      localStorage.removeItem(draft);
      this.composer = null;
      this.draftKey = null;
    });
  },
};
