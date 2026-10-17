-- Make the private kiosk password table's direct-access denial explicit for RLS lints.
drop policy if exists "deny direct kiosk lock access" on private.attendance_screen_locks;
create policy "deny direct kiosk lock access"
  on private.attendance_screen_locks for all to public
  using (false) with check (false);
