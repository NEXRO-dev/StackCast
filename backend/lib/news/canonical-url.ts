const trackingParameters = new Set([
  "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "ref_src",
]);

export function canonicalizeURL(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("NEWS_URL_PROTOCOL_NOT_ALLOWED");
  }

  url.hash = "";
  for (const key of [...url.searchParams.keys()]) {
    if (key.toLowerCase().startsWith("utm_") || trackingParameters.has(key.toLowerCase())) {
      url.searchParams.delete(key);
    }
  }
  url.hostname = url.hostname.toLowerCase();
  url.pathname = url.pathname.replace(/\/{2,}/g, "/").replace(/\/$/, "") || "/";
  url.searchParams.sort();
  return url.toString();
}
