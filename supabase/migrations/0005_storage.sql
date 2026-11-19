-- EZ POS - Phase 1 - 0005: storage buckets (run on Supabase only)
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true), ('business-assets', 'business-assets', true)
on conflict (id) do nothing;

-- Files live under "<business_id>/..." so each business can only write inside its own folder.
create policy "ez_assets_read" on storage.objects for select to public
  using (bucket_id in ('product-images', 'business-assets'));

create policy "ez_assets_insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('product-images', 'business-assets')
              and (storage.foldername(name))[1] = app.current_business_id()::text
              and (app.has_perm('products.manage') or app.has_perm('settings.manage')));

create policy "ez_assets_update" on storage.objects for update to authenticated
  using (bucket_id in ('product-images', 'business-assets')
         and (storage.foldername(name))[1] = app.current_business_id()::text
         and (app.has_perm('products.manage') or app.has_perm('settings.manage')));

create policy "ez_assets_delete" on storage.objects for delete to authenticated
  using (bucket_id in ('product-images', 'business-assets')
         and (storage.foldername(name))[1] = app.current_business_id()::text
         and (app.has_perm('products.manage') or app.has_perm('settings.manage')));
