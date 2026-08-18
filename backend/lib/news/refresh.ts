import { getTurso } from "../turso";
import { GDELTProvider } from "./providers/gdelt";
import { upsertNewsCandidate } from "./repository";

type TopicRow = { id: string; query: string };

export async function refreshSharedNewsPool(): Promise<{ topics: number; fetched: number; stored: number; failures: string[] }> {
  if (process.env.GDELT_PROVIDER_ENABLED === "false") {
    return { topics: 0, fetched: 0, stored: 0, failures: [] };
  }
  const topics = (await getTurso().all(
    `SELECT id, query_en AS query FROM recommendation_topics WHERE is_active = 1 ORDER BY sort_order`,
  )) as TopicRow[];
  const provider = new GDELTProvider();
  let fetched = 0;
  let stored = 0;
  const failures: string[] = [];

  for (const topic of topics) {
    try {
      const candidates = await provider.search({ topicID: topic.id, query: topic.query, language: "japanese", limit: 30 });
      fetched += candidates.length;
      for (const candidate of candidates) {
        try {
          await upsertNewsCandidate(topic.id, provider.name, candidate);
          stored += 1;
        } catch (error) {
          failures.push(`${topic.id}:store:${error instanceof Error ? error.message : String(error)}`);
        }
      }
    } catch (error) {
      failures.push(`${topic.id}:fetch:${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return { topics: topics.length, fetched, stored, failures: failures.slice(0, 50) };
}
