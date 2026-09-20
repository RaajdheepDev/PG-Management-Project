-- Store the resident's actual PG check-in date.
-- Existing residents are left NULL until the admin enters the correct date.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS check_in_date DATE;
