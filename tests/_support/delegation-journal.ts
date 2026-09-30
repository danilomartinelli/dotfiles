import { Database } from "bun:sqlite";

/** Fails real journal writes until the returned cleanup removes the fault. */
export function refuseDelegationWrites(filename: string): () => void {
  const db = new Database(filename);
  try {
    db.exec(`CREATE TRIGGER refuse_delegation_write BEFORE UPDATE ON delegations
      BEGIN SELECT RAISE(ABORT, 'Fixture journal write failure'); END`);
  } finally {
    db.close();
  }
  return () => {
    const reopened = new Database(filename);
    try {
      reopened.exec("DROP TRIGGER refuse_delegation_write");
    } finally {
      reopened.close();
    }
  };
}

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
