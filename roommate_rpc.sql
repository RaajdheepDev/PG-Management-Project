-- Securely expose only the roommate details needed by a resident's My Room page.
-- Residents cannot use this function to request another room; it always uses auth.uid().

CREATE OR REPLACE FUNCTION public.get_my_roommates()
RETURNS TABLE (
  resident_id UUID,
  full_name TEXT,
  resident_type TEXT,
  phone TEXT,
  check_in_date DATE,
  bed_number TEXT,
  bed_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  my_room_id UUID;
BEGIN
  SELECT p.room_id
    INTO my_room_id
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.role = 'resident'
    AND p.resident_status = 'active';

  IF my_room_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.resident_type,
    p.phone,
    p.check_in_date,
    b.bed_number::TEXT,
    b.status::TEXT
  FROM public.beds b
  JOIN public.profiles p
    ON p.id = b.student_id
  WHERE b.room_id = my_room_id
    AND b.student_id IS NOT NULL
    AND b.student_id <> auth.uid()
    AND p.role = 'resident'
    AND p.resident_status = 'active'
  ORDER BY b.bed_number;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_roommates() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_roommates() TO authenticated;
