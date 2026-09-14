-- My Home Boys PG - Cash Payment + Check-in-Date Billing
-- Run this once in Supabase SQL Editor.

-- 1) Official room-type pricing
CREATE TABLE IF NOT EXISTS public.room_type_pricing (
  room_type TEXT PRIMARY KEY,
  monthly_fee NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0)
);

INSERT INTO public.room_type_pricing (room_type, monthly_fee)
VALUES
  ('1 Sharing', 10000),
  ('2 Sharing', 9000),
  ('3 Sharing', 8000)
ON CONFLICT (room_type) DO UPDATE
SET monthly_fee = EXCLUDED.monthly_fee;

ALTER TABLE public.room_type_pricing ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.room_type_pricing TO authenticated;
DROP POLICY IF EXISTS "room_type_pricing_authenticated_read" ON public.room_type_pricing;
CREATE POLICY "room_type_pricing_authenticated_read"
ON public.room_type_pricing
FOR SELECT TO authenticated
USING (true);

-- 2) Payment fields needed by the cash-payment workflow
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'not_submitted';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_date DATE;

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_verification_status_check;
ALTER TABLE public.payments
ADD CONSTRAINT payments_verification_status_check
CHECK (verification_status IN ('not_submitted','pending','verified','rejected'));

-- 3) Allow residents to read only their own payment records.
GRANT SELECT ON public.payments TO authenticated;
DROP POLICY IF EXISTS "payments_resident_read_own" ON public.payments;
CREATE POLICY "payments_resident_read_own"
ON public.payments
FOR SELECT TO authenticated
USING ((select auth.uid()) = student_id OR (select public.is_admin()));

-- 4) Secure admin-only cash verification function.
DROP FUNCTION IF EXISTS public.mark_payment_cash_paid(UUID);
CREATE OR REPLACE FUNCTION public.mark_payment_cash_paid(p_payment_id UUID, p_payment_date DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only an admin can mark a payment as paid by cash';
  END IF;

  UPDATE public.payments
  SET
    status = 'paid',
    payment_method = 'cash',
    verification_status = 'verified',
    payment_date = COALESCE(p_payment_date, CURRENT_DATE),
    verified_at = NOW(),
    utr_number = NULL,
    submitted_at = NULL
  WHERE id = p_payment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_payment_cash_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_payment_cash_paid(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_payment_cash_paid(UUID, DATE) TO authenticated;

-- 5) Generate the current month's rent dues from the resident's room type and check-in date.
--    The due day is the resident's check-in day. If a month is shorter,
--    the due date becomes that month's last day.
--    Unpaid current-month dues are also synchronized to the resident's
--    currently assigned room type fee.
CREATE OR REPLACE FUNCTION public.generate_checkin_date_payment_dues()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_date DATE := CURRENT_DATE;
  month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  month_end DATE := (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;
  month_label TEXT := to_char(month_start, 'FMMonth YYYY');
BEGIN
  -- First, keep unpaid current-month dues aligned with the resident's
  -- current room type and check-in-day due date.
  UPDATE public.payments pay
  SET
    amount = rtp.monthly_fee,
    due_date = LEAST(
      month_end,
      month_start + (EXTRACT(DAY FROM p.check_in_date)::INT - 1)
    )
  FROM public.profiles p
  JOIN public.rooms r ON r.id = p.room_id
  JOIN public.room_type_pricing rtp ON rtp.room_type = r.room_type
  WHERE pay.student_id = p.id
    AND pay.month = month_label
    AND pay.status IN ('pending', 'overdue')
    AND p.role = 'resident'
    AND p.resident_status = 'active'
    AND p.check_in_date IS NOT NULL;

  -- Generate the current-month due only when its check-in-date due date
  -- has arrived (or passed). The daily Cron job will catch every resident.
  INSERT INTO public.payments (
    student_id,
    amount,
    month,
    status,
    due_date,
    payment_method,
    verification_status
  )
  SELECT
    p.id,
    rtp.monthly_fee,
    month_label,
    CASE
      WHEN calculated_due_date < today_date THEN 'overdue'
      ELSE 'pending'
    END,
    calculated_due_date,
    NULL,
    'not_submitted'
  FROM public.profiles p
  JOIN public.rooms r ON r.id = p.room_id
  JOIN public.room_type_pricing rtp ON rtp.room_type = r.room_type
  CROSS JOIN LATERAL (
    SELECT LEAST(
      month_end,
      month_start + (EXTRACT(DAY FROM p.check_in_date)::INT - 1)
    )::DATE AS calculated_due_date
  ) d
  WHERE p.role = 'resident'
    AND p.resident_status = 'active'
    AND p.check_in_date IS NOT NULL
    AND d.calculated_due_date <= today_date
    AND NOT EXISTS (
      SELECT 1
      FROM public.payments pay
      WHERE pay.student_id = p.id
        AND pay.month = month_label
    );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_checkin_date_payment_dues() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_generate_checkin_date_payment_dues()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only an admin can generate payment dues';
  END IF;
  PERFORM public.generate_checkin_date_payment_dues();
END;
$$;

REVOKE ALL ON FUNCTION public.admin_generate_checkin_date_payment_dues() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_generate_checkin_date_payment_dues() TO authenticated;

-- 5A) One-time synchronization for existing unpaid current-month records.
--     Paid historical records are intentionally left unchanged.
UPDATE public.payments pay
SET
  amount = rtp.monthly_fee,
  due_date = LEAST(
    (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE,
    date_trunc('month', CURRENT_DATE)::DATE
      + (EXTRACT(DAY FROM p.check_in_date)::INT - 1)
  )
FROM public.profiles p
JOIN public.rooms r ON r.id = p.room_id
JOIN public.room_type_pricing rtp ON rtp.room_type = r.room_type
WHERE pay.student_id = p.id
  AND pay.month = to_char(date_trunc('month', CURRENT_DATE), 'FMMonth YYYY')
  AND pay.status IN ('pending', 'overdue')
  AND p.role = 'resident'
  AND p.resident_status = 'active'
  AND p.check_in_date IS NOT NULL;

-- 6) Generate the current month's dues now for existing residents.
SELECT public.generate_checkin_date_payment_dues();

-- 7) OPTIONAL: enable pg_cron first from Supabase Dashboard > Integrations > Cron.
--    Then schedule the function DAILY. It will only create a payment when
--    today's date is the resident's calculated check-in-date due date,
--    or when an existing resident's current-month due has not yet been created.
--
-- SELECT cron.schedule(
--   'generate-checkin-date-payment-dues-daily',
--   '30 0 * * *',
--   $$SELECT public.generate_checkin_date_payment_dues();$$
-- );
