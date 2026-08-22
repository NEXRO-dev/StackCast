import assert from "node:assert/strict";
import test from "node:test";
import { canonicalizeURL } from "../lib/news/canonical-url";
import {
  newsRefreshBuildDecision,
  newsRefreshIsWithinCooldown,
  newsRefreshProviderUnavailable,
  newsRefreshProviderUnderfilled,
  type NewsRefreshResult,
} from "../lib/news/refresh";
import {
  dailyEditionStatusForSelection,
  isDailyEditionCatchUpTime,
  tokyoEditionDate,
} from "../lib/recommendations/daily-edition";

test("canonical URL removes tracking and fragments", () => {
  assert.equal(
    canonicalizeURL("https://Example.com/news/?utm_source=test&b=2&a=1#section"),
    "https://example.com/news?a=1&b=2",
  );
});

test("canonical URL rejects non-web protocols", () => {
  assert.throws(() => canonicalizeURL("file:///tmp/article"), /NEWS_URL_PROTOCOL_NOT_ALLOWED/);
});

test("Tokyo edition date changes at JST midnight", () => {
  assert.equal(tokyoEditionDate(new Date("2026-08-18T14:59:59Z")), "2026-08-18");
  assert.equal(tokyoEditionDate(new Date("2026-08-18T15:00:00Z")), "2026-08-19");
});

test("daily edition catch-up window covers local 16:15 through 16:29", () => {
  assert.equal(isDailyEditionCatchUpTime(new Date("2026-08-18T07:14:59Z"), "Asia/Tokyo"), false);
  assert.equal(isDailyEditionCatchUpTime(new Date("2026-08-18T07:15:00Z"), "Asia/Tokyo"), true);
  assert.equal(isDailyEditionCatchUpTime(new Date("2026-08-18T07:29:59Z"), "Asia/Tokyo"), true);
  assert.equal(isDailyEditionCatchUpTime(new Date("2026-08-18T07:30:00Z"), "Asia/Tokyo"), false);
});

test("news refresh cooldown lasts six hours and force bypasses it", () => {
  const lastSuccess = "2026-08-18T00:00:00.000Z";
  assert.equal(newsRefreshIsWithinCooldown(lastSuccess, new Date("2026-08-18T05:59:59.999Z")), true);
  assert.equal(newsRefreshIsWithinCooldown(lastSuccess, new Date("2026-08-18T06:00:00.000Z")), false);
  assert.equal(newsRefreshIsWithinCooldown(lastSuccess, new Date("2026-08-18T01:00:00.000Z"), true), false);
  assert.equal(newsRefreshIsWithinCooldown(lastSuccess, new Date("2026-08-18T01:00:00.000Z"), false, 4), false);
  assert.equal(newsRefreshIsWithinCooldown("invalid", new Date("2026-08-18T01:00:00.000Z")), false);
});

test("provider failure forces a fallback rebuild while cooldown does not rebuild", () => {
  const unavailable: NewsRefreshResult = {
    topics: 3,
    fetched: 0,
    stored: 0,
    failures: ["gdelt:timeout", "openai:429"],
    cooldown: false,
  };
  assert.equal(newsRefreshProviderUnavailable(unavailable), true);
  assert.equal(newsRefreshProviderUnderfilled(unavailable), false);
  assert.deepEqual(newsRefreshBuildDecision(unavailable), { forceRebuild: true, markFallback: true });

  const cooldown: NewsRefreshResult = { ...unavailable, failures: [], cooldown: true };
  assert.equal(newsRefreshProviderUnavailable(cooldown), false);
  assert.equal(newsRefreshProviderUnderfilled(cooldown), false);
  assert.deepEqual(newsRefreshBuildDecision(cooldown), { forceRebuild: false, markFallback: false });
});

test("partial provider refresh rebuilds as fallback", () => {
  const underfilled: NewsRefreshResult = {
    topics: 3,
    fetched: 1,
    stored: 1,
    failures: ["technology:gdelt:timeout"],
    cooldown: false,
  };
  assert.equal(newsRefreshProviderUnavailable(underfilled), false);
  assert.equal(newsRefreshProviderUnderfilled(underfilled), true);
  assert.deepEqual(newsRefreshBuildDecision(underfilled), { forceRebuild: true, markFallback: true });
});

test("stored provider articles force a ready rebuild", () => {
  const refreshed: NewsRefreshResult = {
    topics: 3,
    fetched: 5,
    stored: 5,
    failures: [],
    cooldown: false,
  };
  assert.equal(newsRefreshProviderUnavailable(refreshed), false);
  assert.deepEqual(newsRefreshBuildDecision(refreshed), { forceRebuild: true, markFallback: false });
  assert.equal(dailyEditionStatusForSelection(5, false), "ready");
});

test("cache-backed selections can be explicitly marked as fallback", () => {
  assert.equal(dailyEditionStatusForSelection(5, true), "fallback");
  assert.equal(dailyEditionStatusForSelection(4, false), "fallback");
  assert.equal(dailyEditionStatusForSelection(0, true), "failed");
});
