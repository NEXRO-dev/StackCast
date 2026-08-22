import assert from "node:assert/strict";
import test from "node:test";
import { GDELTProvider } from "../lib/news/providers/gdelt";
import { GroqWebSearchProvider } from "../lib/news/providers/groq-web-search";
import { OpenAIWebSearchProvider } from "../lib/news/providers/openai-web-search";

const input = {
  topicID: "topic-1",
  query: "technology",
  language: "english" as const,
  sourceCountry: "UnitedStates",
  limit: 3,
};

test("Groq web search collects multiple article URLs per topic", async () => {
  let calls = 0;
  const requestBodies: Record<string, unknown>[] = [];

  await withGroqKey(async () => {
    await withFetchMock(async (_request, init) => {
      calls += 1;
      requestBodies.push(parseRequestBody(init));
      return successfulGroqResponse([
        { topicID: calls === 1 ? "topic-1" : "topic-2", url: `https://example.com/${calls}-a?utm_source=test`, title: `Article ${calls}A`, description: "News", publishedAt: "2026-08-22T00:00:00Z" },
        { topicID: calls === 1 ? "topic-1" : "topic-2", url: `https://example.com/${calls}-b`, title: `Article ${calls}B`, description: "News", publishedAt: "2026-08-22T00:00:00Z" },
        { topicID: calls === 1 ? "topic-1" : "topic-2", url: "https://example.com/duplicate", title: "Duplicate", description: "News", publishedAt: "2026-08-22T00:00:00Z" },
      ]);
    }, async () => {
      const articles = await new GroqWebSearchProvider().searchTopics([
        { ...input, topicID: "topic-1", limit: 4 },
        { ...input, topicID: "topic-2", query: "business", limit: 4 },
      ]);
      assert.equal(articles.length, 5);
      assert.deepEqual(articles.map((article) => article.topicID), ["topic-1", "topic-1", "topic-1", "topic-2", "topic-2"]);
      assert.deepEqual(articles.map((article) => article.sourceDomain), [
        "example.com", "example.com", "example.com", "example.com", "example.com",
      ]);
    });
  });

  assert.equal(calls, 2);
  assert.deepEqual(requestBodies.map((body) => body.model), ["groq/compound-mini", "groq/compound-mini"]);
  assert.deepEqual(requestBodies.map((body) => (body.response_format as { type?: string }).type), ["json_object", "json_object"]);
});

test("Groq 429 preserves safe diagnostics and is not retried", async () => {
  let calls = 0;

  await withGroqKey(async () => {
    await withFetchMock(async () => {
      calls += 1;
      return new Response(JSON.stringify({
        error: {
          code: "rate_limit_exceeded",
          type: "requests",
          message: "ERROR_MESSAGE_MUST_NOT_BE_LOGGED",
        },
      }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "7",
          "x-request-id": "req.test/123",
          "x-ratelimit-remaining-requests": "0",
          "x-ratelimit-reset-requests": "42s",
        },
      });
    }, async () => {
      await assert.rejects(
        new GroqWebSearchProvider().search(input),
        (error: unknown) => {
          assert.ok(error instanceof Error);
          assert.equal(error.name, "GroqNewsRequestError");
          assert.match(error.message, /GROQ_NEWS_REQUEST_FAILED_429/u);
          assert.match(error.message, /CODE_rate_limit_exceeded/u);
          assert.match(error.message, /TYPE_requests/u);
          assert.match(error.message, /RETRY_AFTER_MS_7000/u);
          assert.match(error.message, /REQUEST_ID_req_test_123/u);
          assert.match(error.message, /REMAINING_REQUESTS_0/u);
          assert.match(error.message, /RESET_REQUESTS_42s/u);
          assert.doesNotMatch(error.message, /ERROR_MESSAGE_MUST_NOT_BE_LOGGED/u);
          assert.equal((error as Error & { status?: number }).status, 429);
          return true;
        },
      );
    });
  });

  assert.equal(calls, 1);
});

test("Groq continues with later topics after one topic fails", async () => {
  let calls = 0;

  await withGroqKey(async () => {
    await withFetchMock(async () => {
      calls += 1;
      if (calls === 1) {
        return new Response(JSON.stringify({ error: { code: "rate_limit_exceeded", type: "requests" } }), {
          status: 429,
          headers: { "content-type": "application/json" },
        });
      }
      return successfulGroqResponse([
        { topicID: "topic-2", url: "https://example.com/recovered", title: "Recovered", description: "News", publishedAt: "2026-08-22T00:00:00Z" },
      ]);
    }, async () => {
      const articles = await new GroqWebSearchProvider().searchTopics([
        { ...input, topicID: "topic-1", query: "technology", limit: 4 },
        { ...input, topicID: "topic-2", query: "business", limit: 4 },
      ]);
      assert.equal(articles.length, 1);
      assert.equal(articles[0]?.topicID, "topic-2");
      assert.equal(articles[0]?.url, "https://example.com/recovered");
    });
  });

  assert.equal(calls, 2);
});

test("GDELT bounds the search window and does not retry non-429 4xx responses", async () => {
  let calls = 0;
  let requestedURL: URL | undefined;
  const originalTimespan = process.env.GDELT_TIMESPAN;
  const originalInterval = process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
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
  delete process.env.GDELT_TIMESPAN;
  process.env.GDELT_MIN_REQUEST_INTERVAL_MS = "0";

  try {
    await assert.rejects(
      new GDELTProvider().search({ ...input, query: "(technology OR AI OR software)" }),
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
    if (originalTimespan === undefined) delete process.env.GDELT_TIMESPAN;
    else process.env.GDELT_TIMESPAN = originalTimespan;
    if (originalInterval === undefined) delete process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
    else process.env.GDELT_MIN_REQUEST_INTERVAL_MS = originalInterval;
  }

  assert.equal(calls, 1);
  assert.equal(requestedURL?.searchParams.get("timespan"), "1d");
  assert.equal(requestedURL?.searchParams.get("query"), "(technology OR AI OR software) sourcelang:english sourcecountry:UnitedStates");
});

test("GDELT timeout is isolated and does not block the next topic", async () => {
  let calls = 0;
  const originalTimeout = process.env.GDELT_REQUEST_TIMEOUT_MS;
  const originalCooldown = process.env.GDELT_FAILURE_COOLDOWN_MS;
  const originalInterval = process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
  const originalFetch = globalThis.fetch;
  process.env.GDELT_REQUEST_TIMEOUT_MS = "1000";
  process.env.GDELT_FAILURE_COOLDOWN_MS = "60000";
  process.env.GDELT_MIN_REQUEST_INTERVAL_MS = "0";
  globalThis.fetch = async () => {
    calls += 1;
    if (calls === 1) {
      const error = new Error("timeout");
      error.name = "TimeoutError";
      throw error;
    }
    return new Response(JSON.stringify({
      articles: [{
        url: "https://example.com/next-topic",
        title: "Next topic succeeded",
        domain: "example.com",
        seendate: "20260822T010000Z",
      }],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  try {
    await assert.rejects(
      new GDELTProvider().search(input),
      (error: unknown) => error instanceof Error
        && error.name === "GDELTConnectTimeoutError"
        && error.message === "GDELT_CONNECT_TIMEOUT",
    );
    const result = await new GDELTProvider().search({ ...input, topicID: "topic-2", query: "business" });
    assert.equal(result.length, 1);
    assert.equal(result[0]?.title, "Next topic succeeded");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalTimeout === undefined) delete process.env.GDELT_REQUEST_TIMEOUT_MS;
    else process.env.GDELT_REQUEST_TIMEOUT_MS = originalTimeout;
    if (originalCooldown === undefined) delete process.env.GDELT_FAILURE_COOLDOWN_MS;
    else process.env.GDELT_FAILURE_COOLDOWN_MS = originalCooldown;
    if (originalInterval === undefined) delete process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
    else process.env.GDELT_MIN_REQUEST_INTERVAL_MS = originalInterval;
  }

  assert.equal(calls, 2);
});

test("GDELT Node connect timeout is normalized and is not retried", async () => {
  let calls = 0;
  const originalInterval = process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
  const originalFetch = globalThis.fetch;
  process.env.GDELT_MIN_REQUEST_INTERVAL_MS = "0";
  globalThis.fetch = async () => {
    calls += 1;
    const cause = new Error("Connect Timeout Error");
    cause.name = "ConnectTimeoutError";
    const error = new TypeError("fetch failed", { cause });
    throw error;
  };

  try {
    await assert.rejects(
      new GDELTProvider().search(input),
      (error: unknown) => {
        assert.ok(error instanceof Error);
        assert.equal(error.name, "GDELTConnectTimeoutError");
        assert.equal(error.message, "GDELT_CONNECT_TIMEOUT");
        return true;
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalInterval === undefined) delete process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
    else process.env.GDELT_MIN_REQUEST_INTERVAL_MS = originalInterval;
  }

  assert.equal(calls, 1);
});

test("GDELT combines multiple interest topics into one request", async () => {
  let calls = 0;
  let requestedURL: URL | undefined;
  const originalInterval = process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
  const originalFetch = globalThis.fetch;
  process.env.GDELT_MIN_REQUEST_INTERVAL_MS = "0";
  globalThis.fetch = async (request) => {
    calls += 1;
    requestedURL = new URL(String(request));
    return new Response(JSON.stringify({
      articles: [
        { url: "https://example.com/ai", title: "New AI technology", domain: "example.com" },
        { url: "https://example.com/market", title: "Market business report", domain: "example.com" },
        { url: "https://example.com/local", title: "地域社会のニュース", domain: "example.com" },
      ],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  try {
    const result = await new GDELTProvider().searchTopics([
      { ...input, topicID: "technology", query: "technology OR AI", limit: 5 },
      { ...input, topicID: "business", query: "business OR market", limit: 5 },
      { ...input, topicID: "society", query: "society", limit: 5 },
    ]);
    assert.equal(result.length, 3);
    assert.deepEqual(result.map((article) => article.topicID), ["technology", "business", "society"]);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalInterval === undefined) delete process.env.GDELT_MIN_REQUEST_INTERVAL_MS;
    else process.env.GDELT_MIN_REQUEST_INTERVAL_MS = originalInterval;
  }

  assert.equal(calls, 1);
  assert.match(requestedURL?.searchParams.get("query") ?? "", /technology OR AI/u);
  assert.match(requestedURL?.searchParams.get("query") ?? "", /business OR market/u);
  assert.match(requestedURL?.searchParams.get("query") ?? "", /society/u);
  assert.equal(requestedURL?.searchParams.get("maxrecords"), "15");
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

async function withGroqKey<T>(operation: () => Promise<T>): Promise<T> {
  const originalAPIKey = process.env.GROQ_API_KEY;
  const originalModel = process.env.GROQ_NEWS_MODEL;
  const originalTotalLimit = process.env.GROQ_NEWS_TOTAL_LIMIT;
  process.env.GROQ_API_KEY = "test-api-key";
  delete process.env.GROQ_NEWS_MODEL;
  delete process.env.GROQ_NEWS_TOTAL_LIMIT;
  try {
    return await operation();
  } finally {
    if (originalAPIKey === undefined) delete process.env.GROQ_API_KEY;
    else process.env.GROQ_API_KEY = originalAPIKey;
    if (originalModel === undefined) delete process.env.GROQ_NEWS_MODEL;
    else process.env.GROQ_NEWS_MODEL = originalModel;
    if (originalTotalLimit === undefined) delete process.env.GROQ_NEWS_TOTAL_LIMIT;
    else process.env.GROQ_NEWS_TOTAL_LIMIT = originalTotalLimit;
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

function successfulGroqResponse(articles: Array<Record<string, string>> = []): Response {
  return new Response(JSON.stringify({
    id: "chatcmpl_test",
    choices: [{
      message: {
        content: JSON.stringify({ articles }),
      },
    }],
  }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
