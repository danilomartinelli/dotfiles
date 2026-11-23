// Preferences a person may change in the installed mod.json under `settings`, read by
// more than one view. `combined` is read by the lists view: tabs, or spaces above agents.
// `agent_name` is read by the agents view: "tab" names a row after its tab, "title" after
// the terminal's live title.
export const DEFAULT_SETTINGS = {
  git: { retry_after: "15s" },
  pull_request_status: true,
  combined: true,
  agent_name: "tab",
};
