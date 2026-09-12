-- ============================================================
-- GreenYield -- crop fallback image storage bucket
-- Public bucket (unlike crop-photos): fallback images are shared,
-- admin-owned assets (one per crop), not user-owned, so there's no
-- per-user RLS to enforce, and public serving skips the extra
-- createSignedUrl round-trip for faster loads. Only the offline
-- upload script (using the service-role key, which bypasses RLS)
-- ever writes to this bucket.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('crop-fallback-images', 'crop-fallback-images', true)
on conflict (id) do nothing;
