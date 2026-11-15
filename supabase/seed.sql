-- ============================================================================
-- Seed: supabase/seed.sql
-- Description: Sample trivia questions covering multiple categories and formats
-- ============================================================================

INSERT INTO questions (category, question_type, question_text, image_url, audio_url, reference_answer, judge_notes)
VALUES
    -- General Knowledge
    ('General Knowledge', 'text', 'What is the capital city of Australia?', NULL, NULL, 'Canberra', 'Accept Canberra only. Sydney or Melbourne are incorrect.'),
    ('General Knowledge', 'text', 'Which element has the chemical symbol "Fe"?', NULL, NULL, 'Iron', 'Latin: Ferrum. Accept Iron.'),
    ('General Knowledge', 'text', 'How many continents are there on Earth?', NULL, NULL, '7', 'Accept seven (Africa, Antarctica, Asia, Australia/Oceania, Europe, North America, South America).'),

    -- Science & Nature
    ('Science', 'text', 'What planet is known as the Red Planet?', NULL, NULL, 'Mars', 'Accept Mars.'),
    ('Science', 'text', 'What is the fastest land animal?', NULL, NULL, 'Cheetah', 'Accept Cheetah.'),
    ('Science', 'text', 'What is the powerhouse of the cell?', NULL, NULL, 'Mitochondria', 'Accept Mitochondria or Mitochondrion.'),

    -- Geography & History
    ('History', 'text', 'In which year did the Titanic sink?', NULL, NULL, '1912', 'Accept 1912 (April 15).'),
    ('History', 'text', 'Who was the first President of the United States?', NULL, NULL, 'George Washington', 'Accept George Washington or Washington.'),
    ('Geography', 'text', 'Which is the longest river in the world?', NULL, NULL, 'Nile River', 'Accept Nile or Amazon if disputed, but primary standard is Nile.'),

    -- Pop Culture & Entertainment
    ('Entertainment', 'text', 'Who played Iron Man in the Marvel Cinematic Universe?', NULL, NULL, 'Robert Downey Jr.', 'Accept Robert Downey Jr. or RDJ.'),
    ('Entertainment', 'text', 'What is the fictional name of Harry Potter''s owl?', NULL, NULL, 'Hedwig', 'Accept Hedwig.'),

    -- Image Questions (Using public royalty-free Wikimedia sample images)
    ('Geography', 'image', 'Name this famous landmark located in Paris, France.', 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/85/Tour_Eiffel_Wikimedia_Commons_%28cropped%29.jpg/600px-Tour_Eiffel_Wikimedia_Commons_%28cropped%29.jpg', NULL, 'Eiffel Tower', 'Accept Eiffel Tower or Tour Eiffel.'),
    ('Art', 'image', 'Who painted this famous portrait known as the Mona Lisa?', 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg/600px-Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg', NULL, 'Leonardo da Vinci', 'Accept Leonardo da Vinci or Da Vinci.'),

    -- Audio Trivia (Using public domain / royalty free audio clip)
    ('Music', 'audio', 'Listen to this clip: Identify the musical instrument playing.', NULL, 'https://upload.wikimedia.org/wikipedia/commons/2/21/Acoustic_guitar_chord.ogg', 'Acoustic Guitar', 'Accept Guitar or Acoustic Guitar.');
