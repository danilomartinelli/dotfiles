import type { PluginInput } from "@opencode-ai/plugin";
import path from "node:path";
import {
  canonical,
  openDelegations,
  type Delegation,
  type Delegations,
  type Routes,
} from "./delegations";

type Session = NonNullable<
  Awaited<ReturnType<PluginInput["client"]["session"]["get"]>>["data"]
>;

/** Children keep the root project's journal, even in a different native project. */
export class SessionJournals {
  private journals = new Map<string, Promise<Delegations>>();
  private sessions = new Map<string, Promise<Session>>();
  onStopped?: (row: Delegation) => Promise<void>;

  constructor(
    private directory: string,
    private client: PluginInput["client"],
    private routes: Routes,
  ) {}

  project(projectID: string): Promise<Delegations> {
    if (!/^[a-zA-Z0-9_-]{1,128}$/.test(projectID))
      throw new Error("Invalid native project identity.");
    let pending = this.journals.get(projectID);
    if (!pending) {
      pending = openDelegations(
        path.join(this.directory, `${projectID}.sqlite`),
        this.client,
        this.routes,
      ).then((manager) => {
        manager.onStopped = (row) => this.onStopped?.(row) ?? Promise.resolve();
        return manager;
      });
      this.journals.set(projectID, pending);
      pending.catch(() => this.journals.delete(projectID));
    }
    return pending;
  }

  session(sessionID: string): Promise<Session> {
    let pending = this.sessions.get(sessionID);
    if (!pending) {
      pending = this.client.session
        .get({ path: { id: sessionID } })
        .then((response) => {
          if (
            response.error ||
            !response.data ||
            response.data.id !== sessionID
          )
            throw new Error("Cannot resolve native session identity.");
          return response.data;
        });
      this.sessions.set(sessionID, pending);
      pending.catch(() => this.sessions.delete(sessionID));
    }
    return pending;
  }

  async forSession(sessionID: string): Promise<Delegations> {
    const session = await this.session(sessionID);
    const root = session.parentID
      ? await this.session(session.parentID)
      : session;
    if (root.parentID) throw new Error("Leaf sessions cannot create children.");
    const manager = await this.project(root.projectID);
    if (session.parentID) {
      const child = manager.forChild(sessionID);
      // A delegation records its directory canonically, so the native session's
      // spelling has to be canonicalised to be comparable. Resolving only the
      // relative segments would report a child reached through a symlink as a
      // delegation defect.
      const directory = await canonical(session.directory);
      if (!child || child.root !== root.id || child.directory !== directory)
        throw new Error(
          "Child session has no matching root delegation; enter child roles through delegate.",
        );
    }
    return manager;
  }

  async close() {
    for (const manager of await Promise.all(this.journals.values()))
      manager.close();
    this.journals.clear();
    this.sessions.clear();
  }
}
