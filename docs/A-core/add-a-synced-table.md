# How to Add a Synced Table

**Owner:** Author A (Core)
**Reviewers:** whichever author owns the new feature
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`, sync-config (path unconfirmed)

## 1. Purpose

A checklist for adding a new table that syncs through PowerSync. The registry is only one of about nine touchpoints. Background: [data-access.md](data-access.md), [powersync-sync-and-mirrors.md](powersync-sync-and-mirrors.md).

## 2. Decide first

| Question | If yes |
|---|---|
| Does the client need to read it offline? | Sync it (this checklist). |
| Must a user read *other users'* rows of a profile-like table? | Do not sync; use a `SECURITY DEFINER` RPC. |
| Will the client write it directly? | It needs INSERT **and** UPDATE RLS policies (uploads are upserts), and a registry entry. |
| Is it written only by SQL functions/RPCs (orders, wallet, delivery)? | Sync read-only; no client write policy. |

## 3. Checklist

| # | Where | What |
|---|---|---|
| 1 | `supabase/migrations/<ts>_<name>.sql` | `create table`, `enable row level security`, select policy, plus insert/update/delete policies only if the client writes. Add `set_updated_at` trigger if you have `updated_at`. Grant execute on any functions. |
| 2 | Same or next migration | **Mirror columns** for every enum or geography column: `*_text` / `*_geojson` column, trigger function, `before insert or update of <cols>` trigger, backfill `update t set col = col`. |
| 3 | Publication | `alter publication powersync add table public.<t>;` (do not drop/recreate). |
| 4 | PowerSync sync config (YAML) | Add a stream. Rules: no alias on the source table; INNER JOIN only; no `EXISTS`; no `COALESCE`, casts or date math; select only from the source table; alias mirrors (`status_text as status`); split `OR` conditions across two streams if they need different joins. If the Postgres PK is not `id`, alias it (`profile_id as id`). |
| 5 | `lib/core/local_db/powersync_schema.dart` | `Table('<t>', [...])`, `Column.text/real/integer` only. Booleans are `integer`; enums, uuids, timestamps and jsonb are `text`. |
| 6 | `lib/core/local_db/table_registry.dart` | `TableConfig(tableName, remotePkColumn, jsonbColumns, compositeKey)`. Needed for any table the client may write; also prevents a `StateError` from `configFor()` on an accidental write. Read-only tables (wallet, chat, pricing) are currently omitted. |
| 7 | `lib/models/<t>.dart` | `fromMap` (tolerate `num` vs `String`, integer booleans), `toInsertMap` without the pk. |
| 8 | `lib/features/<f>/<f>_service.dart` | `Repository<T>` or raw `db.watch/execute`. |
| 9 | Riverpod provider | `StreamProvider(.family/.autoDispose)`. |
| 10 | Docs | Add the table to the relevant area doc and to [powersync-sync-and-mirrors.md](powersync-sync-and-mirrors.md). |

## 4. Verification checklist

- Every column in `powersync_schema.dart` is also selected by the stream. Missing columns are silently null locally. This has happened for `orders.order_date` and the `delivery` display names, see the mismatch table in [powersync-sync-and-mirrors.md](powersync-sync-and-mirrors.md).
- Every column the client writes exists in Postgres, and its RLS `with check` passes.
- For composite keys: the stream builds the id (`a || ':' || b as id`), the registry has `CompositeKey([...])`, and the service builds ids with `configFor(...).compositeKey!.buildId(...)`.
- Insert order respects foreign keys (the queue uploads in local write order).
- For jsonb columns: listed in `jsonbColumns`.

## 5. Worked examples from this repo

| Table | Notes |
|---|---|
| `farmer_review` (`20260916152234`) | Read-only on the client: RLS select is public, no write policies, writes go through `submit_farmer_review`. It is in the registry (see the data-access caveat), published via `ALTER PUBLICATION ... ADD TABLE`, and synced by `own_farmer_reviews`. |
| `farmer_crop` | Composite PK, no `id`: stream builds the id, registry has `compositeKey`. Needed an UPDATE policy