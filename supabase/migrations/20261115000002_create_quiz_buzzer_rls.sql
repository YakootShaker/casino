-- ============================================================================
-- Migration: 20261115000002_create_quiz_buzzer_rls.sql
-- Description: Row-Level Security policies enforcing strict Content Isolation
--              between Referee and Players Console devices.
-- ============================================================================

-- 1. Enable RLS on all tables
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_log ENABLE ROW LEVEL SECURITY;

-- 2. Rooms Policies
-- Allow paired devices (referee or console) to read room metadata
CREATE POLICY "Allow paired devices to read room"
ON rooms FOR SELECT
USING (
    auth.uid() = referee_uid OR auth.uid() = console_uid
);

-- 3. Game States Policies
-- Allow paired devices to read live game state
CREATE POLICY "Allow paired devices to read game state"
ON game_states FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM rooms
        WHERE rooms.id = game_states.room_id
          AND (rooms.referee_uid = auth.uid() OR rooms.console_uid = auth.uid())
    )
);

-- 4. Questions Table - STRICT CONTENT ISOLATION
-- Only the Referee can query questions, clues, and reference answers!
-- The Players Console has zero read permission on this table.
CREATE POLICY "Allow only referee to read questions"
ON questions FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM rooms
        WHERE rooms.referee_uid = auth.uid()
    )
);

-- 5. Room Questions Table
CREATE POLICY "Allow referee to read room questions"
ON room_questions FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM rooms
        WHERE rooms.id = room_questions.room_id
          AND rooms.referee_uid = auth.uid()
    )
);

-- 6. Score Log Policies
CREATE POLICY "Allow paired devices to view score log"
ON score_log FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM rooms
        WHERE rooms.id = score_log.room_id
          AND (rooms.referee_uid = auth.uid() OR rooms.console_uid = auth.uid())
    )
);
