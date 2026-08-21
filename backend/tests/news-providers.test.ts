import assert from "node:assert/strict";
import test from "node:test";
import { GDELTProvider } from "../lib/news/providers/gdelt";
import { OpenAIWebSearchProvider } from "../lib/news/providers/openai-web-search";

const input = {
  topicID: "topic-1",
  query: "technology",
  language: "english" as const,
  sourceCountry: "UnitedStates",
  limit: 3,
};

test("GDELT bounds the search window and does not retry non-429 4xx responses", async () => {
  let calls = 0;
  let requestedURL: URL | undefined;
  const originalFetch = globalThis.fetch;
  const mockFetch: typeof fetch = async (request) => {
    calls += 1;
    requestedURL = new URL(String(request));
    return new Response("RESPONSE_BODY_MUST_NOT_BE_LOGGED", {
      status: 400,
      headers: {
        "retry-after": "7",
        "x-request-id": "req.test/123",
      },
    });
  };
  globalThis.fetch = mockFetch;

  try {
    await assert.rejects(
      new GDELTProvider().search(input),
      (error: unknown) => {
        assert.ok(error instanceof Error);
        assert.equal(error.name, "GDELTRequestError");
        assert.match(error.message, /GDELT_REQUEST_FAILED_400/u);
        assert.match(error.message, /RETRY_AFTER_MS_7000/u);
        assert.match(error.message, /REQUEST_ID_reqtest123/u);
        assert.doesNotMatch(error.message, /RESPONSE_BODY_MUST_NOT_BE_LOGGED/u);
        assert.equal((error as Error & { status?: number }).status, 400);
        return true;
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  assert.equal(calls, 1);
  assert.equal(requestedURL?.searchParams.get("timespan"), "2d");
});

test("OpenAI quota 429 preserves safe diagnostics and is not retried", async () => {
  let calls = 0;
  let requestBody: Record<string, unknown> | undefined;

  await withOpenAIKey(async () => {
    await withFetchMock(async (_request, init) => {
      calls += 1;
      requestBody = parseRequestBody(init);
      return new Response(JSON.stringify({
        error: {
          code: "credit_balance_exhausted",
          type: "insufficient_quota",
          message: "ERROR_MESSAGE_MUST_NOT_BE_LOGGED",
        },
      }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "7",
          "x-request-id": "req.test/123",
        },
      });
    }, async () => {
      await assert.rejects(
        new OpenAIWebSearchProvider().search(input),
        (error: unknown) => {
          assert.ok(error instanceof Error);
          assert.equal(error.name, "OpenAINewsRequestError");
          assert.match(error.message, /OPENAI_NEWS_REQUEST_FAILED_429/u);
          assert.match(error.message, /CODE_credit_balance_exhausted/u);
          assert.match(error.message, /TYPE_insufficient_quota/u);
          assert.match(error.message, /RETRY_AFTER_MS_7000/u);
          assert.match(error.message, /REQUEST_ID_req_test_123/u);
          assert.doesNotMatch(error.message, /ERROR_MESSAGE_MUST_NOT_BE_LOGGED/u);
          assert.equal((error as Error & { status?: number }).status, 429);
          return true;
        },
      );
    });
  });

  assert.equal(calls, 1);
  assert.equal(requestBody?.max_tool_calls, 1);
});

test("OpenAI transient 429 retries once and caps multi-topic web searches", async () => {
  let calls = 0;
  const requestBodies: Record<string, unknown>[] = [];

  await withOpenAIKey(async () => {
    await withFetchMock(async (_request, init) => {
      calls += 1;
      requestBodies.push(parseRequestBody(init));
      if (calls === 1) {
        return new Response(JSON.stringify({
          error: { code: "rate_limit_exceeded", type: "requests" },
        }), {
          status: 429,
          headers: { "content-type": "application/json", "retry-after": "0" },
        });
      }
      return successfulOpenAIResponse([
        { topicID: "topic-1", url: "https://example.com/a", title: "A", description: "A", publishedAt: "2026-08-21T00:00:00Z" },
        { topicID: "topic-2", url: "https://example.com/b", title: "B", description: "B", publishedAt: "2026-08-21T00:00:00Z" },
        { topicID: "topic-3", url: "https://example.com/c", title: "C", description: "C", publishedAt: "2026-08-21T00:00:00Z" },
        { topicID: "topic-4", url: "https://example.com/d", title: "D", description: "D", publishedAt: "2026-08-21T00:00:00Z" },
        { topicID: "topic-1", url: "https://example.com/e", title: "E", description: "E", publishedAt: "2026-08-21T00:00:00Z" },
      ]);
    }, async () => {
      const articles = await new OpenAIWebSearchProvider().searchTopics([
        input,
        { ...input, topicID: "topic-2" },
        { ...input, topicID: "topic-3" },
        { ...input, topicID: "topic-4" },
      ]);
      assert.equal(articles.length, 5);
    });
  });

  assert.equal(calls, 2);
  assert.deepEqual(requestBodies.map((body) => body.max_tool_calls), [3, 3]);
});

test("OpenAI multi-topic fallback fills underfilled results with topic searches", async () => {
  let calls = 0;
  const requestBodies: Record<string, unknown>[] = [];

  await withOpenAIKey(async () => {
    await withFetchMock(async (_request, init) => {
      calls += 1;
      requestBodies.push(parseRequestBody(init));
      if (calls === 1) {
        return successfulOpenAIResponse([
          { topicID: "topic-1", url: "https://example.com/a?utm_source=test", title: "A", description: "A", publishedAt: "2026-08-21T00:00:00Z" },
        ]);
      }
      return successfulOpenAIResponse([
        { url: `https://example.com/${calls}`, title: `Article ${calls}`, description: "More news", publishedAt: "2026-08-21T00:00:00Z" },
        { url: "https://example.com/a", title: "Duplicate", description: "Duplicate", publishedAt: "2026-08-21T00:00:00Z" },
      ]);
    }, async () => {
      const articles = await new OpenAIWebSearchProvider().searchTopics([
        { ...input, topicID: "topic-1", limit: 5 },
        { ...input, topicID: "topic-2", limit: 5 },
        { ...input, topicID: "topic-3", limit: 5 },
      ]);
      assert.equal(articles.length, 4);
      assert.deepEqual(articles.map((article) => article.topicID), ["topic-1", "topic-1", "topic-2", "topic-3"]);
      assert.deepEqual(articles.map((article) => article.url), [
        "https://example.com/a?utm_source=test",
        "https://example.com/2",
        "https://example.com/3",
        "https://example.com/4",
      ]);
    });
  });

  assert.equal(calls, 4);
  assert.deepEqual(requestBodies.map((body) => body.max_tool_calls), [3, 1, 1, 1]);
});

test("OpenAI 5xx responses are retried at most once", async () => {
  let calls = 0;

  await withOpenAIKey(async () => {
    await withFetchMock(async () => {
      calls += 1;
      return new Response("RESPONSE_BODY_MUST_NOT_BE_LOGGED", {
        status: 503,
        headers: { "retry-after": "0" },
      });
    }, async () => {
      await assert.rejects(
        new OpenAIWebSearchProvider().search(input),
        (error: unknown) => {
          assert.ok(error instanceof Error);
          assert.equal(error.name, "OpenAINewsRequestError");
          assert.match(error.message, /OPENAI_NEWS_REQUEST_FAILED_503/u);
          assert.doesNotMatch(error.message, /RESPONSE_BODY_MUST_NOT_BE_LOGGED/u);
          return true;
        },
      );
    });
  });

  assert.equal(calls, 2);
});

test("OpenAI network timeouts are retried at most once with a safe error", async () => {
  let calls = 0;

  await withOpenAIKey(async () => {
    await withFetchMock(async () => {
      calls += 1;
      const error = new Error("NETWORK_DETAILS_MUST_NOT_BE_LOGGED");
      error.name = "TimeoutError";
      throw error;
    }, async () => {
      await assert.rejects(
        new OpenAIWebSearchProvider().search(input),
        (error: unknown) => {
          assert.ok(error instanceof Error);
          assert.equal(error.name, "TimeoutError");
          assert.equal(error.message, "OPENAI_NEWS_REQUEST_TIMEOUT");
          assert.doesNotMatch(error.message, /NETWORK_DETAILS_MUST_NOT_BE_LOGGED/u);
          return true;
        },
      );
    });
  });

  assert.equal(calls, 2);
});

async function withFetchMock<T>(mockFetch: typeof fetch, operation: () => Promise<T>): Promise<T> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = mockFetch;
  try {
    return await operation();
  } finally {
    globalThis.fetch = originalFetch;
  }
}

async function withOpenAIKey<T>(operation: () => Promise<T>): Promise<T> {
  const originalAPIKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = "test-api-key";
  try {
    return await operation();
  } finally {
    if (originalAPIKey === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = originalAPIKey;
  }
}

function parseRequestBody(init?: RequestInit): Record<string, unknown> {
  const body = init?.body;
  if (typeof body !== "string") throw new Error("Expected a string request body");
  return JSON.parse(body) as Record<string, unknown>;
}

function successfulOpenAIResponse(articles: Array<Record<string, string>> = []): Response {
  return new Response(JSON.stringify({
    id: "resp_test",
    output: [{
      type: "message",
      content: [{ type: "output_text", text: JSON.stringify({ articles }) }],
    }],
  }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
