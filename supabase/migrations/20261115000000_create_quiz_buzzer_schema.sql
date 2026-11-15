-- ============================================================================
-- Migration: 20261115000000_create_quiz_buzzer_schema.sql
-- Description: Core schema, tables, triggers, and Realtime publication
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Rooms Table
CREATE TABLE IF NOT EXISTS rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_pin VARCHAR(6) NOT NULL,
    referee_uid UUID NOT NULL,
    console_uid UUID,
    selected_categories TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    room_expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '4 hours')
);

-- Partial Unique Index ensuring unexpired PIN uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_active_pin 
ON rooms (room_pin) 
WHERE (NOW() < room_expires_at);

-- 2. Questions Pool Table
CREATE TABLE IF NOT EXISTS questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    question_type TEXT NOT NULL CHECK (question_type IN ('text', 'image', 'audio')),
    question_text TEXT NOT NULL,
    image_url TEXT,
    audio_url TEXT,
    reference_answer TEXT NOT NULL,
    judge_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Room Questions (Game Queue) Table
CREATE TABLE IF NOT EXISTS room_questions (
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    display_order INT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (room_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_room_questions_order 
ON room_questions (room_id, display_order);

-- 4. Unified Mutable Game States Table
CREATE TABLE IF NOT EXISTS game_states (
    room_id UUID PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
    phase TEXT NOT NULL DEFAULT 'lobby' 
        CHECK (phase IN ('lobby', 'question_revealed', 'buzzer_active', 'player_answering', 'judge_evaluating', 'game_over')),
    state_version INT NOT NULL DEFAULT 1,
    player_names TEXT[] NOT NULL DEFAULT '{"Player 1", "Player 2", "Player 3"}',
    player_scores INT[] NOT NULL DEFAULT '{0, 0, 0}',
    current_question_id UUID REFERENCES questions(id) ON DELETE SET NULL,
    active_player_index INT CHECK (active_player_index BETWEEN 0 AND 2),
    locked_player_indices INT[] NOT NULL DEFAULT '{}',
    buzz_expires_at TIMESTAMPTZ,
    winner_player_index INT CHECK (winner_player_index BETWEEN 0 AND 2),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Score Audit Log Table
CREATE TABLE IF NOT EXISTS score_log (
    id BIGSERIAL PRIMARY KEY,
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    question_id UUID REFERENCES questions(id) ON DELETE SET NULL,
    player_index INT NOT NULL CHECK (player_index BETWEEN 0 AND 2),
    delta INT NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Monotonic State Version Trigger
CREATE OR REPLACE FUNCTION trg_increment_state_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.state_version = OLD.state_version + 1;
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_game_states_version ON game_states;
CREATE TRIGGER trg_game_states_version
BEFORE UPDATE ON game_states
FOR EACH ROW
EXECUTE FUNCTION trg_increment_state_version();

-- 7. Realtime Configuration
ALTER TABLE game_states REPLICA IDENTITY FULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'game_states'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE game_states;
    END IF;
END $$;
