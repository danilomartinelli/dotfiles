import { Database } from "bun:sqlite";

/** Moves a recorded deadline into the past, as if the process had been away. */
export function expireDelegation(filename: string, id: string) {
  const db = new Database(filename);
  try {
    const stored = db
      .query("SELECT record FROM delegations WHERE id=?")
      .get(id) as { record: string };
    const record = JSON.parse(stored.record);
    record.deadline = Date.now() - 1;
    db.query("UPDATE delegations SET record=? WHERE id=?").run(
      JSON.stringify(record),
      id,
    );
  } finally {
    db.close();
  }
}
