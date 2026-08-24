-- 20260823_powersync_publication.sql
create publication powersync for table
  public.profile,
  public.profile_role,
  public.farmer_profile,
  public.farmer_crop,
  public.crop,
  public.buyer_profile,
  public.driver_profile,
  public.vehicle,
  public.driver_route_preference;