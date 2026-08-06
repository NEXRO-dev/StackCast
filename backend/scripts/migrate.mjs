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

for (const migrationName of migrationNames) {
  const migration = await readFile(
    fileURLToPath(new URL(migrationName, migrationsUrl)),
    "utf8",
  );
  const statements = migration
    .split(";")
    .map((statement) => statement.trim())
    .filter(Boolean);

  await database.batch(statements, "immediate");
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
