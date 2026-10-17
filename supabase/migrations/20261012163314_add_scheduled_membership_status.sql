-- Future-dated renewals must not compete with the currently active membership.
-- Keep this enum addition in its own migration so later migrations can safely use it.
alter type public.membership_status add value if not exists 'scheduled';
