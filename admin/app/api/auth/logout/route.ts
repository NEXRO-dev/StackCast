import { clearAdminAuthentication, getAdminSession } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

export async function POST(request: Request) {
  const session = await getAdminSession();
  if (session) {
    await writeAuditLog({
      adminEmail: session.email,
      action: "admin_logout",
      targetType: "admin",
      targetId: session.email,
    }).catch((error) => console.error("Unable to write logout audit log", error));
  }
  await clearAdminAuthentication();
  return Response.redirect(new URL("/login", request.url), 303);
}
