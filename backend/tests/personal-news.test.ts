import assert from "node:assert/strict";
import test from "node:test";
import { canonicalizeURL } from "../lib/news/canonical-url";
import { tokyoEditionDate } from "../lib/recommendations/daily-edition";

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
