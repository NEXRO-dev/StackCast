import { connect, type Connection } from "@tursodatabase/serverless";

let connection: Connection | undefined;

export function getDatabase(): Connection {
  if (connection) {
    return connection;
  }

  const url = requiredEnvironmentVariable("TURSO_DATABASE_URL");
  const authToken = requiredEnvironmentVariable("TURSO_AUTH_TOKEN");

  connection = connect({ url, authToken });
  return connection;
}

export function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}
