-- ============================================================
-- GreenYield -- crop photo storage bucket
-- Private bucket; each farmer may only read/write objects under
-- their own <profile_id>/ prefix. farmer_crop.image_url stores that
-- object path (see CropPhotoService.upload), not a public URL --
-- same convention as the 'avatars' bucket.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('crop-photos', 'crop-photos', false)
on conflict (id) do nothing;

create policy "crop_photo_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'crop-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "crop_photo_select_own"
  on storage.objects for select
  using (
    bucket_id = 'crop-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "crop_photo_update_own"
  on storage.objects for update
  using (
    bucket_id = 'crop-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "crop_photo_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'crop-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
