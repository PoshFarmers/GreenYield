-- Allow order participants to see each other's profiles and driver vehicles
create policy "profile_select_order_participants" on profile for select using (
  exists (
    select 1 from orders o
    left join delivery d on d.order_id = o.id
    left join delivery_assignment da on da.delivery_id = d.id and da.is_current = true
    where (
      o.buyer_profile_id = auth.uid() or
      o.farmer_profile_id = auth.uid() or
      da.driver_profile_id = auth.uid()
    ) and (
      profile.id = o.buyer_profile_id or
      profile.id = o.farmer_profile_id or
      profile.id = da.driver_profile_id
    )
  )
);

create policy "vehicle_select_order_participants" on vehicle for select using (
  exists (
    select 1 from delivery_assignment da
    join delivery d on d.id = da.delivery_id
    join orders o on o.id = d.order_id
    where da.vehicle_id = vehicle.id
      and da.is_current = true
      and (
        o.buyer_profile_id = auth.uid() or
        o.farmer_profile_id = auth.uid() or
        da.driver_profile_id = auth.uid()
      )
  )
);
