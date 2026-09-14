-- DANGER: This permanently deletes ALL payment rows from the PG.
-- Run ONLY if you want to reset the payment data and start again.

DELETE FROM public.payments;

-- Verify the reset:
SELECT COUNT(*) AS remaining_payment_records
FROM public.payments;
