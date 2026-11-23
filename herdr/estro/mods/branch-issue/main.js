// Branch Issue: a sidebar for the current checkout and its issue tracker.
// The Linear methods are built from separate files, so a method used here may live in:
//   state/saved.js        filters, the open issue and tabs across reloads
//   linear/discovery.js   which issues this copy is looking at
//   linear/reads.js       loading lists and issues through the helper
//   actions/changes.js    state, priority, assignee and comments
//   actions/agents.js     who is on an issue, and handing work to them
//   actions/worktrees.js  starting work: an issue's checkouts
//   actions/menus.js      the popup menus
//   views/list.js, detail.js, comments.js, worktrees.js   the drawing
// linear/model.js says what Linear's answers mean; views/ui.js holds every look.
// Git runs on the checkout's machine. Linear requests go through a local helper that
// reads LINEAR_API_KEY; the mod never sees the key.
import { View } from "gpui-kit";
import { InputState, TextareaState } from "gpui-base";
import { spaces, panes, nextCommand, layout, shared } from "herdr";
import { loadSettings, duration } from "./settings.js";
import { savedMethods } from "./state/saved.js";
import { discoveryMethods } from "./linear/discovery.js";
import { readMethods } from "./linear/reads.js";
import { changeMethods } from "./actions/changes.js";
import { agentMethods } from "./actions/agents.js";
import { worktreeMethods } from "./actions/worktrees.js";
import { menuMethods } from "./actions/menus.js";
import { listMethods } from "./views/list.js";
import { detailMethods } from "./views/detail.js";
import { commentMethods } from "./views/comments.js";
import { worktreeViewMethods } from "./views/worktrees.js";
import { keyProblem, panelShown } from "./linear/model.js";
import { Busy, Panel } from "./views/ui.js";
import { readGitHubIssues } from "./github/reads.js";
import { renderGitHubPanel } from "./github/panel.js";

const CONTEXT_POLL_MS = 1000;
const REFRESH_INTERVAL_MS = 60000;
const FIRST_LOAD_LIMIT_MS = 30000;
const NOTICE_MS = 5000;
// Better Search asks for one by shared `branch-issue.open`, { space, identifier, at }; older asks are let go.
const ASK_MS = 10000;
const ASK_POLL_MS = 100;
// Preferences a person may change in the installed mod.json under `settings`.
const DEFAULT_SETTINGS = {
  provider: "linear",
  refresh: { every: "60s", search_debounce: "450ms" },
  branch: { max_identifiers: 4 },
  list: { default: { scope: "mine", state: "active", team: "" } },
  worktrees: { root: "~/.herdr/worktrees", open_with: "terminal", move_to_started: false },
};

function activeSpace() {
  const sp = spaces().find((s) => s.active);
  if (!sp) return null;
  const tab = sp.tabs?.find((t) => t.active)?.id;
  const candidates = panes().filter((p) => p.tab === tab && p.cwd);
  const current = candidates.find((p) => p.focused) ?? candidates[0];
  return { ...sp, folder: current?.cwd ?? sp.folder, branch: current?.branch ?? sp.branch };
}

function spaceContextKey(space) {
  if (!space) return "";
  return `${space.machine ?? "local"}:${space.id}:${space.folder}:${space.branch ?? ""}`;
}

class LinearIssues extends View {
  init(_props, cx) {
    this.view = localStorage.getItem("view") === "all" ? "all" : "branch";
    this.reopenSaved = true;
    this.closedGroups = new Set(this.readStoredList("closed-groups"));
    this.branchIssues = [];
    this.items = [];
    this.cursor = "";
    this.cache = {};
    this.teams = [];
    this.listToken = 0;
    this.detailToken = 0;
    this.branchToken = 0;
    this.searchToken = 0;

    this.menuFocus = cx.focus_handle();
    this.scopeTrigger = cx.focus_handle();
    this.stateTrigger = cx.focus_handle();
    this.teamTrigger = cx.focus_handle();
    this.statePick = cx.focus_handle();
    this.priorityPick = cx.focus_handle();
    this.assigneePick = cx.focus_handle();

    this.settings = DEFAULT_SETTINGS;
    this.settingsProblems = [];
    this.scope = DEFAULT_SETTINGS.list.default.scope;
    this.state = DEFAULT_SETTINGS.list.default.state;
    this.team = DEFAULT_SETTINGS.list.default.team;
    this.section = "overview";
    this.search = InputState.new({ placeholder: "Search · ENG-123, 123 or text" });
    this.search.on("change", (_e, cx) => {
      if (!this.restoringSearch) this.searchChanged(cx);
    });
    this.linkInput = InputState.new({ placeholder: "ENG-123" });
    this.linkInput.on("submit", (_e, cx) => this.linkIssue(cx));
    this.editor = TextareaState.new({ placeholder: "Write a comment…", rows: 4 });
    this.editor.on("change", (_e, cx) => {
      if (this.draftKey) localStorage.setItem(this.draftKey, this.editor.value());
      cx.notify();
    });
    // Its own state, so a new comment stays put while a reply or handoff is being written.
    this.newComment = TextareaState.new({ placeholder: "Write a comment…", rows: 4 });
    this.newComment.on("change", (_e, cx) => {
      if (this.commentKey) localStorage.setItem(this.commentKey, this.newComment.value());
      cx.notify();
    });
    this.startPolling(cx);
    this.listenForCommands(cx);
    this.applySettings(cx);
  }

  // Read the installed mod.json once; list defaults apply until a saved view exists.
  applySettings(cx) {
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("branch-issue", DEFAULT_SETTINGS);
      this.settings = settings;
      this.settingsProblems = problems;
      if (settings.provider !== "linear" && settings.provider !== "github")
        this.settingsProblems.push('settings.provider must be "linear" or "github"');
      this.settingsReady = true;
      const sp = activeSpace();
      if (settings.provider === "github") this.refreshGitHub(cx, sp);
      else this.changeSpace(sp, spaceContextKey(sp), cx);
      cx.notify();
    });
  }

  refreshGitHub(cx, sp = activeSpace()) {
    const key = spaceContextKey(sp);
    if (this.github?.key === key && this.github.loading) return;
    const request = {
      key,
      loading: Boolean(sp?.folder),
      refreshed: Date.now(),
      data: this.github?.key === key ? this.github.data : undefined,
    };
    this.github = request;
    cx.notify();
    if (!request.loading) return;
    cx.spawn(async (cx) => {
      let data, error;
      try {
        data = await readGitHubIssues(sp);
      } catch (e) {
        error = e.message || String(e);
      }
      if (this.github !== request) return;
      const current = activeSpace();
      if (spaceContextKey(current) !== key) {
        this.refreshGitHub(cx, current);
        return;
      }
      Object.assign(request, { loading: false, data, error });
      cx.notify();
    });
  }

  // Better Search's ask, looked for often so the panel turns to it at once.
  takeAsk(cx) {
    const ask = shared("branch-issue.open");
    if (!ask || ask.at <= (this.askedAt ?? 0)) return;
    // Follow the space first, as the slower look does, so it can't cancel this load after.
    const sp = activeSpace();
    const key = spaceContextKey(sp);
    if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
    // A write in progress finishes first; the ask waits for the next look.
    if (ask?.identifier && ask.space === sp?.id && ask.at > (this.askedAt ?? 0) && Date.now() - ask.at < ASK_MS && !this.mutating) {
      this.askedAt = ask.at;
      // What was open last time mustn't replace what was asked for when the list loads.
      this.reopenSaved = false;
      this.restoreSelection = null;
      // As a click in the list does: what was open goes, and the loading line shows until it's here.
      if (this.issue) this.rememberView();
      this.issue = null;
      this.composer = null;
      this.notice = null;
      this.opening = { identifier: ask.identifier };
      this.openIssue(ask.identifier, cx);
      cx.notify();
    }
  }

  startPolling(cx) {
    cx.timer.every(ASK_POLL_MS, (cx) => this.takeAsk(cx));
    cx.timer.every(CONTEXT_POLL_MS, (cx) => {
      if (!this.settingsReady) return;
      const sp = activeSpace();
      const key = spaceContextKey(sp);
      const interval = duration(this.settings.refresh.every, REFRESH_INTERVAL_MS);
      if (this.settings.provider === "github") {
        const due = sp?.folder && this.github && !this.github.loading &&
          Date.now() - this.github.refreshed > interval && panelShown(layout(), "branch-issue");
        if (key !== this.github?.key || due) this.refreshGitHub(cx, sp);
        return;
      }
      // A read that never answers mustn't leave the tabs locked; the helper itself
      // gives up after 26 seconds.
      if (Date.now() - this.contextSince > FIRST_LOAD_LIMIT_MS) {
        this.listLoaded = true;
        this.branchLoaded = true;
      }
      // A confirmation says its piece and goes; an error stays until it's dealt with.
      if (this.notice !== this.noticeShown) {
        this.noticeShown = this.notice;
        this.noticeSince = Date.now();
      } else if (this.notice && Date.now() - this.noticeSince > NOTICE_MS) {
        this.notice = null;
        cx.notify();
      }
      if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
      this.rememberView();
      const minute = Math.floor(Date.now() / 60000);
      if (minute !== this.updatedMinute && this.lastUpdated) {
        this.updatedMinute = minute;
        cx.notify();
      }
      const due = Date.now() - (this.refreshed ?? 0) > interval;
      // Coming back to a hidden panel makes it due at once, if it's been a while.
      if (!this.busy && !this.mutating && due && panelShown(layout(), "branch-issue"))
        this.refresh(cx);
    });
  }

  listenForCommands(cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "refresh" && this.settingsReady) {
          if (this.settings.provider === "github") this.refreshGitHub(cx);
          else this.refresh(cx);
        }
        cx.notify();
      }
    });
  }

  get busy() {
    return this.branchLoading || this.searchPending || this.loading || this.detailLoading;
  }

  render() {
    const root = Panel({ id: "issue-root" });
    if (!this.settingsReady) return root.child(Busy("Loading issue settings…"));
    if (this.settings.provider === "github")
      return renderGitHubPanel(root, this.github, this.settingsProblems, (cx) => this.refreshGitHub(cx));
    const problem = keyProblem(this.error);
    if (problem) return this.renderKeyProblem(root, problem);
    if (this.issue) return this.renderDetail(root);
    return this.opening ? this.renderOpening(root) : this.renderList(root);
  }
}

Object.assign(
  LinearIssues.prototype,
  savedMethods,
  discoveryMethods,
  readMethods,
  changeMethods,
  agentMethods,
  worktreeMethods,
  menuMethods,
  listMethods,
  detailMethods,
  commentMethods,
  worktreeViewMethods,
);

export default LinearIssues;
