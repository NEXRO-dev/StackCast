import { randomUUID } from "node:crypto";
import { getDatabase } from "@/lib/db";

export function auditStatement(input: {
  adminEmail: string;
  action: string;
  targetType: string;
  targetId: string;
  metadata?: Record<string, unknown>;
}) {
  return {
    sql: `INSERT INTO admin_audit_logs
      (id, admin_email, action, target_type, target_id, metadata_json, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`,
    args: [
      randomUUID(),
      input.adminEmail,
      input.action,
      input.targetType,
      input.targetId,
      input.metadata ? JSON.stringify(input.metadata) : null,
      new Date().toISOString(),
    ],
  };
}

export async function writeAuditLog(input: Parameters<typeof auditStatement>[0]) {
  const statement = auditStatement(input);
  await getDatabase().run(statement.sql, ...statement.args);
}
