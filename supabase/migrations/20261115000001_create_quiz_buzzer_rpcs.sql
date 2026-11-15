-- ============================================================================
-- Migration: 20261115000001_create_quiz_buzzer_rpcs.sql
-- Description: Transactional PL/pgSQL RPCs for room setup, pairing, buzz arbitration,
--              scoring, turn expiration, and server clock synchronization.
-- ============================================================================

-- Helper: Get authoritative server time
CREATE OR REPLACE FUNCTION get_server_time()
RETURNS TIMESTAMPTZ AS $$
BEGIN
    RETURN CLOCK_TIMESTAMP();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 1. Create Room RPC
CREATE OR REPLACE FUNCTION create_room(
    p_selected_categories TEXT[] DEFAULT '{}',
    p_player_names TEXT[] DEFAULT '{"Player 1", "Player 2", "Player 3"}'
)
RETURNS JSONB AS $$
DECLARE
    v_room_id UUID;
    v_pin VARCHAR(6);
    v_caller_uid UUID;
    v_attempts INT := 0;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Anonymous or authenticated session required';
    END IF;

    -- Generate a collision-free 6-digit PIN
    LOOP
        v_pin := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
        v_attempts := v_attempts + 1;
        IF NOT EXISTS (
            SELECT 1 FROM rooms 
            WHERE room_pin = v_pin AND NOW() < room_expires_at
        ) THEN
            EXIT;
        END IF;
        IF v_attempts > 20 THEN
            RAISE EXCEPTION 'PIN_GENERATION_FAILED: Unable to allocate unique PIN';
        END IF;
    END LOOP;

    -- Insert Room
    INSERT INTO rooms (room_pin, referee_uid, selected_categories)
    VALUES (v_pin, v_caller_uid, p_selected_categories)
    RETURNING id INTO v_room_id;

    -- Insert Initial Game State
    INSERT INTO game_states (
        room_id, 
        phase, 
        player_names, 
        player_scores, 
        locked_player_indices
    )
    VALUES (
        v_room_id, 
        'lobby', 
        p_player_names, 
        '{0, 0, 0}', 
        '{}'
    );

    RETURN jsonb_build_object(
        'room_id', v_room_id,
        'room_pin', v_pin
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 2. Join Room RPC
CREATE OR REPLACE FUNCTION join_room(p_room_pin TEXT)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_caller_uid UUID;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Anonymous or authenticated session required';
    END IF;

    SELECT * INTO v_room
    FROM rooms
    WHERE room_pin = p_room_pin AND NOW() < room_expires_at
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND: Active room with this PIN was not found';
    END IF;

    -- Disallow re-claiming by a different physical console
    IF v_room.console_uid IS NOT NULL AND v_room.console_uid <> v_caller_uid THEN
        RAISE EXCEPTION 'ROOM_ALREADY_CLAIMED: Players console is already connected to this room';
    END IF;

    UPDATE rooms
    SET console_uid = v_caller_uid
    WHERE id = v_room.id;

    RETURN jsonb_build_object(
        'room_id', v_room.id,
        'room_pin', v_room.room_pin,
        'selected_categories', v_room.selected_categories
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 3. Start Game RPC
CREATE OR REPLACE FUNCTION start_game(
    p_room_id UUID,
    p_category TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
    v_first_q_id UUID;
    v_order INT := 1;
    r RECORD;
BEGIN
    -- Verify room exists and caller is Referee
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;
    IF v_room.referee_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only Referee can start the game';
    END IF;

    -- Lock Game State
    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    IF v_state.phase <> 'lobby' THEN
        RAISE EXCEPTION 'INVALID_PHASE: Game has already started';
    END IF;

    -- Populate Room Questions queue if empty
    IF NOT EXISTS (SELECT 1 FROM room_questions WHERE room_id = p_room_id) THEN
        FOR r IN (
            SELECT id FROM questions
            WHERE (p_category IS NULL OR category = p_category)
            ORDER BY RANDOM()
            LIMIT 15
        ) LOOP
            INSERT INTO room_questions (room_id, question_id, display_order)
            VALUES (p_room_id, r.id, v_order);
            v_order := v_order + 1;
        END LOOP;
    END IF;

    -- Pick first uncompleted question
    SELECT question_id INTO v_first_q_id
    FROM room_questions
    WHERE room_id = p_room_id AND is_completed = FALSE
    ORDER BY display_order ASC
    LIMIT 1;

    IF v_first_q_id IS NULL THEN
        RAISE EXCEPTION 'NO_QUESTIONS_AVAILABLE: No questions found for category';
    END IF;

    -- Advance to question_revealed
    UPDATE game_states
    SET phase = 'question_revealed',
        current_question_id = v_first_q_id,
        active_player_index = NULL,
        locked_player_indices = '{}',
        buzz_expires_at = NULL
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'first_question_id', v_first_q_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 4. Arm Buzzer RPC (Referee opens buzzers)
CREATE OR REPLACE FUNCTION arm_buzzer(p_room_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
BEGIN
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;
    IF v_room.referee_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only Referee can arm buzzers';
    END IF;

    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    IF v_state.phase <> 'question_revealed' THEN
        RAISE EXCEPTION 'INVALID_PHASE: Buzzer can only be armed from question_revealed';
    END IF;

    UPDATE game_states
    SET phase = 'buzzer_active',
        active_player_index = NULL,
        buzz_expires_at = NULL
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'phase', 'buzzer_active');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 5. Buzz RPC (Console captures hardware touch)
CREATE OR REPLACE FUNCTION buzz(
    p_room_id UUID,
    p_player_index INT
)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
BEGIN
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;

    -- Only console device can dispatch buzz
    IF v_room.console_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only paired players console can buzz';
    END IF;

    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    IF v_state.phase <> 'buzzer_active' THEN
        RETURN jsonb_build_object('success', false, 'reason', 'BUZZER_NOT_ACTIVE');
    END IF;

    IF p_player_index = ANY(v_state.locked_player_indices) THEN
        RETURN jsonb_build_object('success', false, 'reason', 'PLAYER_LOCKED');
    END IF;

    -- Successfully claim turn: 10s timer starts
    UPDATE game_states
    SET phase = 'player_answering',
        active_player_index = p_player_index,
        buzz_expires_at = NOW() + INTERVAL '10 seconds'
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'player_index', p_player_index);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 6. Judge Mark RPC (Referee grades answer)
CREATE OR REPLACE FUNCTION judge_mark(
    p_room_id UUID,
    p_is_correct BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
    v_active_idx INT;
    v_scores INT[];
    v_new_score INT;
    v_locked INT[];
    v_next_q_id UUID;
    v_winner_idx INT := NULL;
    v_target_score CONSTANT INT := 5;
BEGIN
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;
    IF v_room.referee_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only Referee can judge answers';
    END IF;

    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    IF v_state.phase NOT IN ('player_answering', 'judge_evaluating') THEN
        RAISE EXCEPTION 'INVALID_PHASE: Cannot judge outside answering or evaluating phases';
    END IF;

    v_active_idx := v_state.active_player_index;
    v_scores := v_state.player_scores;
    v_locked := v_state.locked_player_indices;

    IF p_is_correct THEN
        -- Correct (+1)
        v_scores[v_active_idx + 1] := v_scores[v_active_idx + 1] + 1;
        v_new_score := v_scores[v_active_idx + 1];

        INSERT INTO score_log (room_id, question_id, player_index, delta, reason)
        VALUES (p_room_id, v_state.current_question_id, v_active_idx, 1, 'CORRECT_ANSWER');

        -- Mark question completed
        UPDATE room_questions
        SET is_completed = TRUE
        WHERE room_id = p_room_id AND question_id = v_state.current_question_id;

        -- Check Win Condition
        IF v_new_score >= v_target_score THEN
            v_winner_idx := v_active_idx;
            UPDATE game_states
            SET phase = 'game_over',
                player_scores = v_scores,
                winner_player_index = v_winner_idx,
                active_player_index = NULL,
                buzz_expires_at = NULL
            WHERE room_id = p_room_id;

            RETURN jsonb_build_object('success', true, 'phase', 'game_over', 'winner', v_winner_idx);
        END IF;

        -- Check for Next Question
        SELECT question_id INTO v_next_q_id
        FROM room_questions
        WHERE room_id = p_room_id AND is_completed = FALSE
        ORDER BY display_order ASC
        LIMIT 1;

        IF v_next_q_id IS NULL THEN
            -- No more questions, determine high scorer
            UPDATE game_states
            SET phase = 'game_over',
                player_scores = v_scores,
                active_player_index = NULL,
                buzz_expires_at = NULL
            WHERE room_id = p_room_id;

            RETURN jsonb_build_object('success', true, 'phase', 'game_over', 'reason', 'QUESTIONS_EXHAUSTED');
        END IF;

        -- Advance to next question
        UPDATE game_states
        SET phase = 'question_revealed',
            player_scores = v_scores,
            current_question_id = v_next_q_id,
            active_player_index = NULL,
            locked_player_indices = '{}',
            buzz_expires_at = NULL
        WHERE room_id = p_room_id;

        RETURN jsonb_build_object('success', true, 'phase', 'question_revealed', 'next_question_id', v_next_q_id);

    ELSE
        -- Incorrect (-1)
        v_scores[v_active_idx + 1] := v_scores[v_active_idx + 1] - 1;

        INSERT INTO score_log (room_id, question_id, player_index, delta, reason)
        VALUES (p_room_id, v_state.current_question_id, v_active_idx, -1, 'INCORRECT_ANSWER');

        -- Add player to locked indices
        IF NOT (v_active_idx = ANY(v_locked)) THEN
            v_locked := array_append(v_locked, v_active_idx);
        END IF;

        -- If all 3 players failed (0, 1, 2 locked)
        IF cardinality(v_locked) >= 3 THEN
            UPDATE room_questions
            SET is_completed = TRUE
            WHERE room_id = p_room_id AND question_id = v_state.current_question_id;

            SELECT question_id INTO v_next_q_id
            FROM room_questions
            WHERE room_id = p_room_id AND is_completed = FALSE
            ORDER BY display_order ASC
            LIMIT 1;

            IF v_next_q_id IS NULL THEN
                UPDATE game_states
                SET phase = 'game_over',
                    player_scores = v_scores,
                    active_player_index = NULL,
                    buzz_expires_at = NULL
                WHERE room_id = p_room_id;

                RETURN jsonb_build_object('success', true, 'phase', 'game_over', 'reason', 'QUESTIONS_EXHAUSTED');
            END IF;

            UPDATE game_states
            SET phase = 'question_revealed',
                player_scores = v_scores,
                current_question_id = v_next_q_id,
                active_player_index = NULL,
                locked_player_indices = '{}',
                buzz_expires_at = NULL
            WHERE room_id = p_room_id;

            RETURN jsonb_build_object('success', true, 'phase', 'question_revealed', 'next_question_id', v_next_q_id);
        ELSE
            -- Steal Reopen: Reopen buzzer for remaining players
            UPDATE game_states
            SET phase = 'buzzer_active',
                player_scores = v_scores,
                active_player_index = NULL,
                locked_player_indices = v_locked,
                buzz_expires_at = NULL
            WHERE room_id = p_room_id;

            RETURN jsonb_build_object('success', true, 'phase', 'buzzer_active', 'locked', v_locked);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 7. Expire Turn RPC (10s elapsed)
CREATE OR REPLACE FUNCTION expire_turn(p_room_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_state RECORD;
BEGIN
    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    IF v_state.phase <> 'player_answering' THEN
        RETURN jsonb_build_object('success', false, 'reason', 'NOT_ANSWERING');
    END IF;

    -- Validate deadline with 250ms tolerance cushion
    IF NOW() < (v_state.buzz_expires_at - INTERVAL '250 milliseconds') THEN
        RETURN jsonb_build_object('success', false, 'reason', 'TIMER_NOT_ELAPSED');
    END IF;

    -- Transition to judge_evaluating so human Referee makes authoritative ruling
    UPDATE game_states
    SET phase = 'judge_evaluating',
        buzz_expires_at = NULL
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'phase', 'judge_evaluating');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 8. Adjust Score RPC (Manual +/- referee adjustments)
CREATE OR REPLACE FUNCTION adjust_score(
    p_room_id UUID,
    p_player_index INT,
    p_delta INT
)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
    v_scores INT[];
BEGIN
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;
    IF v_room.referee_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only Referee can adjust scores';
    END IF;

    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    v_scores := v_state.player_scores;
    v_scores[p_player_index + 1] := v_scores[p_player_index + 1] + p_delta;

    INSERT INTO score_log (room_id, question_id, player_index, delta, reason)
    VALUES (p_room_id, v_state.current_question_id, p_player_index, p_delta, 'MANUAL_REFEREE_ADJUSTMENT');

    UPDATE game_states
    SET player_scores = v_scores
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'new_scores', v_scores);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 9. Skip Question RPC
CREATE OR REPLACE FUNCTION skip_question(p_room_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_room RECORD;
    v_state RECORD;
    v_next_q_id UUID;
BEGIN
    SELECT * INTO v_room FROM rooms WHERE id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND';
    END IF;
    IF v_room.referee_uid <> auth.uid() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only Referee can skip questions';
    END IF;

    SELECT * INTO v_state FROM game_states WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_NOT_FOUND';
    END IF;

    UPDATE room_questions
    SET is_completed = TRUE
    WHERE room_id = p_room_id AND question_id = v_state.current_question_id;

    SELECT question_id INTO v_next_q_id
    FROM room_questions
    WHERE room_id = p_room_id AND is_completed = FALSE
    ORDER BY display_order ASC
    LIMIT 1;

    IF v_next_q_id IS NULL THEN
        UPDATE game_states
        SET phase = 'game_over',
            active_player_index = NULL,
            buzz_expires_at = NULL
        WHERE room_id = p_room_id;

        RETURN jsonb_build_object('success', true, 'phase', 'game_over');
    END IF;

    UPDATE game_states
    SET phase = 'question_revealed',
        current_question_id = v_next_q_id,
        active_player_index = NULL,
        locked_player_indices = '{}',
        buzz_expires_at = NULL
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object('success', true, 'phase', 'question_revealed', 'next_question_id', v_next_q_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
