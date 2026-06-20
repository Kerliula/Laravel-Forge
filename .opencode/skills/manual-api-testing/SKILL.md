---
name: manual-api-testing
description: >
  Perform manual API testing using curl against real database data.
  Use this skill whenever the user asks to test an API, run manual tests,
  write a test report, validate endpoints, check edge cases, or says anything
  like "test this with curl", "check the API", or "run manual tests".
license: MIT
compatibility: opencode
---

# Manual API Testing with curl

Test real behavior against real data — not just whether endpoints respond, but whether they enforce the right rules.

---

## Step 0 — Confirm Scope

```bash
git diff $(git merge-base HEAD staging) --name-only
```

Tell the user: "Changed files: [list]. I plan to test: [endpoints]. Confirm or adjust?"

**Wait for confirmation before proceeding.**

---

## Step 1 — Read the Implementation, Not Just the Routes

For each changed file, read the full source: controller, service layer, validators, middleware, model.

Extract and document before writing a single test:

- Every `if/else` branch and early return — each is a required test case
- Every validation rule: field presence, type, format, length, range
- Every state machine: what states exist, which transitions are valid, which are illegal
- Every authorization check: route-level, object-level, field-level (what data is filtered per role)
- DB constraints: unique indexes, foreign keys, not-null columns
- Side effects: what else gets created, updated, deleted, or triggered

**This list is the test plan.** Tests not grounded in actual code branches are guesswork.

---

## Step 2 — Get Real Database Data

Query the DB for records covering diverse states. Production-like data has edge cases synthetic data doesn't.

Only create records if no suitable data exists. Document anything created for cleanup.

---

## Step 3 — Test Every Code Branch

For each branch, condition, and rule extracted in Step 1:

**Validation**
- Each required field missing individually (not all at once)
- Each field at exact min/max boundary, one below, one above
- Wrong type: string for int, float for enum, `null` vs empty string vs missing key — these often behave differently
- Malformed formats: invalid email, malformed UUID, wrong date format

**State machines**
- Every valid transition from every valid state
- Every invalid transition: canceling a shipped order, approving an already-rejected item, updating a deleted record
- Operations on records in terminal states

**Authorization**
- No token, expired token, malformed token
- Correct role, wrong resource owner (user A accessing user B's record)
- Correct owner, insufficient role
- Field-level: does the response expose fields this role shouldn't see?

**Idempotency**
- Same POST twice — two records or deduplicated?
- Same PATCH twice — safe?
- Concurrent identical requests if feasible

**References**
- Valid FK, nonexistent FK, soft-deleted FK
- Delete parent, then fetch or reference child

**Injection**
- SQL: `' OR 1=1 --`, `'; DROP TABLE users; --`
- XSS: `<script>alert(1)</script>`
- Oversized: strings at 10×the documented limit, deeply nested JSON


## Step 4 — Apply Business Logic Standards

Don't just verify what the code does. Apply real-world business rules to find what it *should* do but doesn't.
Flag missing behavior as bugs even if no test explicitly required it.

---

**Financial integrity**
- Amounts must never go negative unless the operation is explicitly a refund or credit — test the boundary
- Total must equal the sum of line items — verify the arithmetic in the DB, not just the response
- Discounts cannot exceed the item price; stacked discounts must not produce negative line items
- Tax must apply consistently (pre- or post-discount) across all items in an order
- Currency must be uniform across an order or invoice — mixing currencies is always a bug
- Rounding: verify amounts round correctly (never floor on customer-facing totals, never ceil on taxes where regulations apply)

**Inventory and capacity**
- Stock cannot go below 0 unless overselling is an explicit, documented feature — test the exact boundary
- Overbooking: fire two simultaneous requests for the last available slot — only one should succeed
- Reservations must lock capacity for their full duration — booking seat A from 2–4pm should block rebooking it at 3pm

**Status lifecycle enforcement**
- Verify every state transition that should be blocked actually is: a completed order must not become active again, a shipped item must not be cancelled without a return flow
- Terminal states must be immutable: verify that PATCH/PUT on a completed, cancelled, or archived record is rejected
- Skipping states must be impossible: pending → completed without going through active must fail
- Cancellation should trigger expected reversals — refund initiated, inventory restored, slot freed

**Ownership and data isolation**
- Beyond role checks: user A with a valid token must not read, modify, or reference user B's records by guessing IDs
- In multi-tenant systems: tenant A must see zero data from tenant B even with a valid admin token scoped to tenant A
- Soft-deleted records must be invisible to all standard queries — not filterable, not referenceable, not counted in totals
- Admins accessing deleted records must use an explicit filter; it must not be the default behavior

**Concurrency and race conditions**
- Balance and inventory changes: fire two requests simultaneously that would both succeed individually — verify only one does
- Double-spend: two payment attempts for the same order at the same moment — verify exactly one charge
- Idempotency keys on payment and webhook endpoints: same key sent twice must return the same result, not trigger a second operation

**Temporal logic**
- End date must be after start date — test equal, one second before, and one day before
- Operations scheduled in the past: decide if this is valid and verify the system agrees consistently
- Datetimes must be stored in UTC and returned with timezone info — verify a record written at UTC+3 is returned correctly to a UTC−5 client
- Expiry: verify expired tokens, coupons, and sessions are rejected at the boundary (not just well before or well after)

**Reversibility and audit**
- Every destructive operation (delete, status change, payment, bulk update) must produce an audit log entry — verify it was created
- Refund amount must not exceed the original charge — test exact amount, one cent over, and full reversal
- Partial refunds: total refunded across multiple calls must not exceed original; verify the running total is tracked
- Bulk operations with partial failures must either roll back entirely or document exactly which records failed — verify the behavior matches the contract

**Cascades and orphans**
- Deleting a parent: verify child records are either cascade-deleted, nullified, or the deletion is blocked — never silently orphaned
- Re-creating after soft delete: verify whether this resurrects the old record (with its history) or creates a new one — either is valid, but it must be consistent and intentional
- Computed fields and denormalized totals: after any mutation to a line item, verify the parent aggregate (order total, account balance, seat count) was updated — not just eventually, but synchronously within the same request

## Step 5 — Test Format

~~~markdown
### [METHOD] /endpoint — what this tests

```bash
curl -X POST https://api.example.com/endpoint \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"field": "value"}'
```

**Expected:** `422` — field must be positive  
**Actual:** `200` — record created with field = 0  
**Result:** ❌ FAIL — no validation; invalid record written to DB
~~~

Verdicts: `✅ PASS` / `❌ FAIL` / `⚠️ UNEXPECTED`

---

## Step 6 — Report

Produce a `.md` file with:

**Summary** — total / pass / fail / unexpected; critical issues at the top.

**Environment** — base URL, auth method, branch, changed files, DB records used or created.

**Test Cases** — full test blocks grouped by endpoint.

---

**Technical Findings**
- Validations missing, wrong, or bypassable
- Wrong HTTP semantics: `200` for not-found, `200` for validation errors, `500` for expected failures
- Data exposed to wrong roles; fields that should be filtered
- Security: missing auth checks, injection risk, over-permissive behavior
- DB writes of logically invalid data that passed validation

**Technical Recommendations**
Go beyond "add validation here." Reason about the design and suggest concrete improvements:
- If multiple endpoints share the same missing validation, recommend centralizing it in middleware or a shared validator rather than patching each route
- If error response shapes are inconsistent across endpoints, propose a standard error envelope and show what it should look like
- If a security gap exists (missing ownership check, exposed field), explain the exploit path — what an attacker could actually do — then recommend the fix
- If a DB constraint is missing (e.g. no unique index backing a uniqueness check done in application code), flag the race condition this creates and recommend the constraint
- If an N+1 pattern is visible from response latency or query logs, name the relationship causing it and suggest eager loading or a join
- If the same logic appears duplicated across controllers, recommend extracting it to a service and explain why consistency matters there specifically

---

**Business Findings**
- Business rules not enforced: illegal state transitions allowed, duplicates created, ownership not checked
- Side effects that didn't happen: counter not updated, related record not created, audit log missing
- Response data inconsistent with what was written to DB
- Behavior that will confuse API consumers or break downstream clients

**Business Recommendations**
Don't just name the gap — explain what goes wrong in the real world if it stays unfixed, then recommend what the correct behavior should be:
- If a terminal state is mutable, describe the real scenario where this breaks: a refunded order being re-shipped, a cancelled subscription still generating invoices
- If an audit log is missing, explain what becomes impossible without it: disputing a charge, reconstructing what changed during an incident, meeting a compliance requirement
- If a race condition allows double-spend or overselling, describe the financial or operational exposure and recommend idempotency keys or a DB-level lock
- If the API returns inconsistent data shapes that would break a client, describe the integration failure mode and recommend a versioning or migration strategy
- If a business rule is enforced in the API but not at the DB level, flag that it can be bypassed by direct DB access or a future script and recommend where the constraint should live
- If behavior differs from what a standard user would expect based on how similar systems work (e-commerce, SaaS billing, booking systems), name the convention and recommend aligning with itat will confuse API consumers or break downstream clients