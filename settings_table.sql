-- PG Settings table used by Admin -> Settings
CREATE TABLE IF NOT EXISTS public.pg_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  pg_name TEXT NOT NULL DEFAULT 'My Home Boys PG',
  default_rent NUMERIC(10,2) NOT NULL DEFAULT 8500,
  pg_address TEXT,
  admin_name TEXT,
  admin_phone TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.pg_settings ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON TABLE public.pg_settings TO authenticated;

DROP POLICY IF EXISTS "pg_settings_admin_all" ON public.pg_settings;
CREATE POLICY "pg_settings_admin_all"
ON public.pg_settings
FOR ALL
TO authenticated
USING ((SELECT public.is_admin()))
WITH CHECK ((SELECT public.is_admin()));

INSERT INTO public.pg_settings (id, pg_name, default_rent, admin_name)
VALUES (1, 'My Home Boys PG', 8500, 'PG Admin')
ON CONFLICT (id) DO NOTHING;
