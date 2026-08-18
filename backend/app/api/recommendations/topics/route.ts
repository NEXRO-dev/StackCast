import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function GET() {
  const topics = await getTurso().all(
    `SELECT id, name_ja AS nameJA, name_en AS nameEN, sort_order AS sortOrder
     FROM recommendation_topics WHERE is_active = 1 ORDER BY sort_order`,
  );
  return Response.json({ topics });
}
