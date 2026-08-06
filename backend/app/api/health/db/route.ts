import { getTurso } from "@/lib/turso";

export async function GET() {
  try {
    const result = await getTurso().get("SELECT 1 AS ok");

    return Response.json({
      status: "ok",
      database: "turso",
      connected: result?.ok === 1,
    });
  } catch (error) {
    console.error("Turso health check failed", error);

    return Response.json(
      {
        status: "error",
        database: "turso",
        connected: false,
      },
      { status: 503 },
    );
  }
}
