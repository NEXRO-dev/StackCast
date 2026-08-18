import assert from "node:assert/strict";
import test from "node:test";
import { resolveEffectiveSubscription, type EffectiveSubscriptionRow } from "../lib/billing/effective-plan";

const now = new Date("2026-08-18T00:00:00.000Z");

function subscription(overrides: Partial<EffectiveSubscriptionRow>): EffectiveSubscriptionRow {
  return {
    billingPlanTier: "plus",
    entitlementId: "StashCast Pro",
    billingStatus: "active",
    billingIsActive: 1,
    expiresAt: "2026-08-19T00:00:00.000Z",
    billingUpdatedAt: "2026-08-17T00:00:00.000Z",
    ...overrides,
  };
}

test("active RevenueCat Plus resolves to Plus", () => {
  const result = resolveEffectiveSubscription(subscription({}), now);
  assert.equal(result.effectivePlanTier, "plus");
  assert.equal(result.effectiveIsActive, true);
  assert.equal(result.source, "revenuecat");
});

test("expired RevenueCat Plus resolves to Free", () => {
  const result = resolveEffectiveSubscription(subscription({
    billingStatus: "expired",
    billingIsActive: 0,
    expiresAt: "2026-08-17T00:00:00.000Z",
  }), now);
  assert.equal(result.effectivePlanTier, "free");
  assert.equal(result.effectiveIsActive, false);
});

test("active admin override wins over RevenueCat", () => {
  const result = resolveEffectiveSubscription(subscription({
    overridePlanTier: "pro",
    overrideIsActive: 1,
    overrideExpiresAt: "2026-08-20T00:00:00.000Z",
    overrideUpdatedAt: "2026-08-18T00:00:00.000Z",
  }), now);
  assert.equal(result.effectivePlanTier, "pro");
  assert.equal(result.effectiveIsActive, true);
  assert.equal(result.source, "admin_override");
});

test("admin Free override revokes an active RevenueCat plan", () => {
  const result = resolveEffectiveSubscription(subscription({
    overridePlanTier: "free",
    overrideIsActive: 0,
    overrideExpiresAt: "2026-08-20T00:00:00.000Z",
  }), now);
  assert.equal(result.effectivePlanTier, "free");
  assert.equal(result.effectiveIsActive, false);
  assert.equal(result.source, "admin_override");
});

test("no current override falls back to RevenueCat", () => {
  const result = resolveEffectiveSubscription(subscription({
    overridePlanTier: null,
    overrideIsActive: null,
    overrideExpiresAt: null,
  }), now);
  assert.equal(result.effectivePlanTier, "plus");
  assert.equal(result.source, "revenuecat");
});
