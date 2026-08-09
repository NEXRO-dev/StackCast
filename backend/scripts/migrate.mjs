import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { connect } from "@tursodatabase/serverless";

const databaseUrl = requiredEnvironmentVariable("TURSO_DATABASE_URL");
const authToken = requiredEnvironmentVariable("TURSO_AUTH_TOKEN");
const database = connect({ url: databaseUrl, authToken });
const migrationsUrl = new URL("../db/migrations/", import.meta.url);
const migrationNames = (await readdir(fileURLToPath(migrationsUrl)))
  .filter((name) => !name.startsWith(".") && name.endsWith(".sql"))
  .sort();

await database.run(`
  CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY NOT NULL,
    applied_at TEXT NOT NULL
  )
`);

for (const migrationName of migrationNames) {
  const alreadyApplied = await database.get(
    "SELECT name FROM schema_migrations WHERE name = ? LIMIT 1",
    migrationName,
  );

  if (alreadyApplied) {
    console.log(`Skipped ${migrationName}; already applied.`);
    continue;
  }

  const migration = await readFile(
    fileURLToPath(new URL(migrationName, migrationsUrl)),
    "utf8",
  );
  const statements = migration
    .split(";")
    .map((statement) => statement.trim())
    .filter(Boolean);

  await database.batch(statements, "immediate");
  await database.run(
    "INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)",
    migrationName,
    new Date().toISOString(),
  );
  console.log(`Applied ${migrationName} successfully.`);
}

console.log("All migrations applied successfully.");

function requiredEnvironmentVariable(name) {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}
