// Branch PR: a pull-request sidebar, for the current branch and the whole
// repository. The class is built from separate files, so a method used here may
// live in any of:
//   state/saved.js        filters, the open PR and read markers across reloads
//   github/discovery.js   which repository and PR this copy is looking at
//   github/reads.js       loading lists, details, jobs and logs through the helper
//   actions/changes.js    merging, closing, reviews and comments
//   actions/agents.js     who is on a PR, and handing work to them
//   actions/worktrees.js  a PR's checkouts
//   actions/menus.js      the popup menus
//   views/list.js, detail.js, conversation.js, checks.js, worktrees.js   the drawing
//   views/files.js        the Files tab, and handing a file's diff to Better Changes
// github/model.js says what GitHub's answers mean; views/ui.js holds every look.
import { View } from "gpui-kit";
import { InputState, TextareaState } from "gpui-base";
import { spaces, panes, nextCommand, layout, readTextFile, appHome, shared } from "herdr";
import { loadSettings, duration } from "./settings.js";
import { followFileIcons } from "./file-icons.js";
import { savedMethods } from "./state/saved.js";
import { discoveryMethods } from "./github/discovery.js";
import { readMethods } from "./github/reads.js";
import { changeMethods } from "./actions/changes.js";
import { agentMethods } from "./actions/agents.js";
import { worktreeMethods } from "./actions/worktrees.js";
import { menuMethods } from "./actions/menus.js";
import { listMethods } from "./views/list.js";
import { detailMethods } from "./views/detail.js";
import { conversationMethods } from "./views/conversation.js";
import { checksMethods } from "./views/checks.js";
import { worktreeViewMethods } from "./views/worktrees.js";
import { filesMethods } from "./views/files.js";
import { panelShown, ghProblem } from "./github/model.js";
import { Panel } from "./views/ui.js";

const CONTEXT_POLL_MS = 1000;
const REFRESH_INTERVAL_MS = 60000;
const FIRST_LOAD_LIMIT_MS = 30000;
const NOTICE_MS = 5000;
// Better Search asks for one by shared `branch-pr.open`, { space, number, repo, at }; older asks are let go.
const ASK_MS = 10000;
const ASK_POLL_MS = 100;
// Preferences a person may change in the installed mod.json under `settings`.
const DEFAULT_SETTINGS = {
  refresh: { every: "60s", search_debounce: "450ms" },
  list: { page_size: 25, default: { tab: "all", state: "open" } },
  worktrees: { root: "~/.herdr/worktrees", open_with: "terminal" },
  logs: { keep_last: "60KB" },
  tools: { github: "gh" },
};

// Each space's last terminal folder and branch.
const lastTerminal = new Map();

function activeSpace() {
  const sp = spaces().find((s) => s.active);
  if (!sp) return null;
  const tab = sp.tabs?.find((t) => t.active)?.id;
  const candidates = panes().filter((p) => p.tab === tab && p.cwd);
  const current = candidates.find((p) => p.focused) ?? candidates[0];
  if (current) lastTerminal.set(sp.id, { folder: current.cwd, branch: current.branch });
  // A tab with no terminal, such as a diff, keeps the last one's, so the PR isn't read again.
  const last = lastTerminal.get(sp.id);
  return { ...sp, folder: last?.folder ?? sp.folder, branch: last?.branch ?? sp.branch };
}

function spaceContextKey(space) {
  if (!space) return "";
  return `${space.machine ?? "local"}:${space.id}:${space.folder}:${space.branch ?? ""}`;
}

class PullRequests extends View {
  init(_props, cx) {
    this.view = localStorage.getItem("view") === "all" ? "all" : "branch";
    this.reopenSaved = true;
    this.closedGroups = new Set(this.readStoredList("closed-groups"));
    this.entryOpen = {};
    this.branchPRs = [];
    this.remotes = [];
    this.items = [];
    this.cursors = {};
    this.cache = {};
    this.listToken = 0;
    this.detailToken = 0;
    this.repoToken = 0;
    this.branchToken = 0;
    this.searchToken = 0;

    this.menuFocus = cx.focus_handle();
    this.remoteTrigger = cx.focus_handle();
    this.scopeTrigger = cx.focus_handle();
    this.stateTrigger = cx.focus_handle();
    this.authorTrigger = cx.focus_handle();

    this.workflowOpen = {};
    this.checkOpen = {};
    this.jobs = {};
    this.logs = {};
    this.author = "";
    this.section = "overview";
    this.fileLayout = localStorage.getItem("files-layout") === "flat" ? "flat" : "tree";
    this.closedFolders = new Set();
    // Better Icons' pictures for the Files tab, when it's installed.
    followFileIcons(this, cx);
    this.settings = DEFAULT_SETTINGS;
    this.settingsProblems = [];
    this.tab = DEFAULT_SETTINGS.list.default.tab;
    this.state = DEFAULT_SETTINGS.list.default.state;
    this.applySettings(cx);
    // shortcut: checked once, so installing Better Changes takes effect after the next reload.
    this.hasBetterChanges = false;
    readTextFile(`${appHome()}/mods/better-changes/mod.json`)
      .then((raw) => (this.hasBetterChanges = raw !== null))
      .catch(() => {});
    this.search = InputState.new({ placeholder: "Search · #482, text, author:login" });
    this.search.on("change", (_e, cx) => {
      if (!this.restoringSearch) this.searchChanged(cx);
    });
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
    // Its own state, so a squash message never mixes with a comment draft.
    this.squashMessage = TextareaState.new({ placeholder: "Commit message", rows: 6 });
    this.squashMessage.on("change", (_e, cx) => cx.notify());
    this.startPolling(cx);
    this.listenForCommands(cx);

    const space = activeSpace();
    this.changeSpace(space, spaceContextKey(space), cx);
  }

  // Read the installed mod.json once; list defaults apply until a saved view exists.
  applySettings(cx) {
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("branch-pr", DEFAULT_SETTINGS);
      this.settings = settings;
      this.settingsProblems = problems;
      // Only while nothing has been chosen yet, by a saved view or a click.
      const untouched =
        !this.viewWasSaved &&
        this.tab === DEFAULT_SETTINGS.list.default.tab &&
        this.state === DEFAULT_SETTINGS.list.default.state;
      const { tab, state } = settings.list.default;
      if (untouched && (tab !== this.tab || state !== this.state)) {
        this.tab = tab;
        this.state = state;
        // The first load may already have used the shipped defaults.
        if (this.view === "all" && this.repo) this.loadList(cx);
      }
      cx.notify();
    });
  }

  // Better Search's ask, looked for often so the panel turns to it at once.
  takeAsk(cx) {
    const ask = shared("branch-pr.open");
    if (!ask || ask.at <= (this.askedAt ?? 0)) return;
    // Follow the space first, as the slower look does, so it can't cancel this load after.
    const sp = activeSpace();
    const key = spaceContextKey(sp);
    if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
    // A write in progress finishes first; the ask waits for the next look.
    if (ask?.number && ask.space === sp?.id && ask.at > (this.askedAt ?? 0) && Date.now() - ask.at < ASK_MS && !this.mutating) {
      this.askedAt = ask.at;
      // What was open last time mustn't replace what was asked for when the list loads.
      this.reopenSaved = false;
      this.restoreSelection = null;
      // As a click in the list does: what was open goes, and "Loading #N…" shows until it's here.
      if (this.pr) this.leavePR();
      this.pr = null;
      this.composer = null;
      this.jobs = {};
      this.logs = {};
      this.notice = null;
      this.opening = { number: ask.number };
      this.openPR(ask.number, cx, ask.repo || this.repo);
      cx.notify();
    }
  }

  startPolling(cx) {
    cx.timer.every(ASK_POLL_MS, (cx) => this.takeAsk(cx));
    cx.timer.every(CONTEXT_POLL_MS, (cx) => {
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
      const sp = activeSpace();
      const key = spaceContextKey(sp);
      if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
      this.rememberView();
      const minute = Math.floor(Date.now() / 60000);
      if (minute !== this.updatedMinute && this.lastUpdated) {
        this.updatedMinute = minute;
        cx.notify();
      }
      const due =
        Date.now() - (this.refreshed ?? 0) >
        duration(this.settings.refresh.every, REFRESH_INTERVAL_MS);
      // Coming back to a hidden panel makes it due at once, if it's been a while.
      if (!this.busy && !this.mutating && due && panelShown(layout(), "branch-pr"))
        this.refresh(cx);
    });
  }

  listenForCommands(cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "refresh") this.refresh(cx);
        cx.notify();
      }
    });
  }

  get busy() {
    return (
      this.repoLoading ||
      this.branchLoading ||
      this.searchPending ||
      this.loading ||
      this.detailLoading
    );
  }

  render() {
    const root = Panel({ id: "pr-root" });
    const problem = ghProblem(this.error);
    if (problem) return this.renderGhProblem(root, problem);
    if (this.pr) return this.renderDetail(root);
    return this.opening ? this.renderOpening(root) : this.renderList(root);
  }
}

Object.assign(
  PullRequests.prototype,
  savedMethods,
  discoveryMethods,
  readMethods,
  changeMethods,
  agentMethods,
  worktreeMethods,
  menuMethods,
  listMethods,
  detailMethods,
  conversationMethods,
  checksMethods,
  worktreeViewMethods,
  filesMethods,
);

export default PullRequests;
