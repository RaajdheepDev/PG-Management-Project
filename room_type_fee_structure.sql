-- My Home Boys PG: official room type / monthly fee structure
-- 1 Sharing = ₹10,000
-- 2 Sharing = ₹9,000
-- 3 Sharing = ₹8,000
-- The website derives the fee from room_type, so no fee needs to be entered manually.

-- First inspect existing room types before enforcing the new rule:
SELECT room_number, room_type, capacity
FROM public.rooms
ORDER BY room_number;

-- After confirming every existing room is one of the 3 official types,
-- enforce the allowed room types:
ALTER TABLE public.rooms
DROP CONSTRAINT IF EXISTS rooms_room_type_check;

ALTER TABLE public.rooms
ADD CONSTRAINT rooms_room_type_check
CHECK (room_type IN ('1 Sharing', '2 Sharing', '3 Sharing'));

-- Capacity must match the sharing type.
ALTER TABLE public.rooms
DROP CONSTRAINT IF EXISTS rooms_capacity_matches_type;

ALTER TABLE public.rooms
ADD CONSTRAINT rooms_capacity_matches_type
CHECK (
  (room_type = '1 Sharing' AND capacity = 1) OR
  (room_type = '2 Sharing' AND capacity = 2) OR
  (room_type = '3 Sharing' AND capacity = 3)
);
