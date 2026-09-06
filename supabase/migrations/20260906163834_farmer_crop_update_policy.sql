-- ============================================================
-- GreenYield -- fix missing farmer_crop UPDATE policy
--
-- farmer_crop has had select/insert/delete policies since its
-- original migration, but no update policy was ever added -- even
-- after description/default_price_per_kg/image_url columns landed
-- (20260829153627, 20260827085839). With RLS enabled and no matching
-- UPDATE policy, `UPDATE farmer_crop ...` silently matches zero rows
-- (no error), so FarmerProfileService.upsertCrop's edits (price,
-- description, and especially crop photo re-uploads) never actually
-- persisted server-side -- the local optimistic write would show
-- briefly, then get reverted by the next PowerSync download of the
-- unchanged server row.
-- ============================================================

create policy "farmer_crop_update_own"
  on farmer_crop for update
  using (auth.uid() = farmer_profile_id)
  with check (auth.uid() = farmer_profile_id);
