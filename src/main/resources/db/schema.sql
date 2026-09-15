-- LearnTrack database schema
-- Copied verbatim from LearnTrack_Implementation_Plan.md, section 3.
-- Run once on first launch if these tables don't already exist (see MainApp / DBConnection).

CREATE TABLE IF NOT EXISTS semesters (
    semester_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    status        TEXT DEFAULT 'ACTIVE'
);

-- Recurring weekly commitments for NORMAL teaching days. Entered once per semester.
-- Also used for MST/EST topics BEFORE a datesheet exists (see plan section 4).
CREATE TABLE IF NOT EXISTS weekly_timetable (
    entry_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    semester_id     INTEGER NOT NULL,
    day_of_week     TEXT NOT NULL,      -- MONDAY..SUNDAY
    start_time      TEXT NOT NULL,
    end_time        TEXT NOT NULL,
    activity_type   TEXT NOT NULL,      -- CLASS | LAB | MEAL | SLEEP | OTHER
    label           TEXT,
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

CREATE TABLE IF NOT EXISTS weekday_study_preference (
    semester_id   INTEGER NOT NULL,
    day_of_week   TEXT NOT NULL,
    study_hours   REAL NOT NULL,
    PRIMARY KEY (semester_id, day_of_week),
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

-- Simplified fixed routine used ONLY once a real MST/EST datesheet exists.
-- Entered once, applies to every day inside the resulting exam window.
CREATE TABLE IF NOT EXISTS exam_period_routine (
    routine_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    semester_id     INTEGER NOT NULL,
    start_time      TEXT NOT NULL,
    end_time        TEXT NOT NULL,
    activity_type   TEXT NOT NULL,      -- MEAL | SLEEP | OTHER
    label           TEXT,
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

-- One-off changes to a SPECIFIC date: CANCEL frees a recurring block,
-- ADD blocks new time (e.g. a dated exam sitting + its buffer).
CREATE TABLE IF NOT EXISTS date_overrides (
    override_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    override_date  TEXT NOT NULL,
    entry_id       INTEGER,
    action         TEXT NOT NULL,      -- 'CANCEL' | 'ADD'
    start_time     TEXT,
    end_time       TEXT,
    activity_type  TEXT,               -- EXAM | OTHER
    label          TEXT
);

-- exam_type is also the BATCH key: all exams sharing the same exam_type within
-- an active semester ('MST' or 'EST') are treated as one batch for the
-- negotiation loop and the important_flag reset (plan sections 4, 9). A semester
-- typically has at most one MST batch and one EST batch.
CREATE TABLE IF NOT EXISTS exams (
    exam_id              INTEGER PRIMARY KEY AUTOINCREMENT,
    semester_id           INTEGER NOT NULL,
    subject               TEXT NOT NULL,
    exam_type             TEXT NOT NULL,   -- 'NORMAL' | 'MST' | 'EST'
    credits               INTEGER DEFAULT 1,   -- entered upfront for EVERY exam type
    eval_marks             REAL DEFAULT 0,      -- entered upfront for EVERY exam type
    exam_date             TEXT,             -- exact date; NULL until datesheet released (MST/EST only)
    exam_start_time        TEXT,             -- NULL until known
    exam_end_time          TEXT,
    travel_time_minutes    INTEGER DEFAULT 30,
    window_start_date      TEXT,             -- provisional, MST/EST only
    window_end_date        TEXT,
    pyq_remaining_hours    REAL DEFAULT 2,   -- counts down like a topic's remaining_hours
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

CREATE TABLE IF NOT EXISTS topics (
    topic_id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    exam_id                    INTEGER NOT NULL,
    name                       TEXT NOT NULL,
    importance                 INTEGER NOT NULL,
    difficulty                  INTEGER NOT NULL,
    hours_needed               REAL NOT NULL,
    remaining_hours            REAL NOT NULL,       -- LEARNING phase, overwritten on "Not yet"
    phase                      TEXT DEFAULT 'LEARNING',   -- LEARNING | REVISION
    revision_hours_needed      REAL DEFAULT 0,       -- size of ONE revision cycle
    revision_remaining_hours   REAL DEFAULT 0,       -- left to do in the CURRENT cycle
    revision_interval_days     INTEGER DEFAULT 7,
    last_revised                TEXT,                 -- only updated when a revision cycle is CLOSED
    important_flag             INTEGER DEFAULT 1,     -- 0 = temporarily excluded during a negotiation
    FOREIGN KEY (exam_id) REFERENCES exams(exam_id)
);

CREATE TABLE IF NOT EXISTS skills (
    skill_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name             TEXT NOT NULL,
    category         TEXT NOT NULL,
    proficiency      INTEGER NOT NULL,
    last_practiced   TEXT NOT NULL
    -- no semester_id: never deleted on semester rollover, tracked forever
);

CREATE TABLE IF NOT EXISTS daily_log (
    log_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    log_date     TEXT NOT NULL,
    item_type    TEXT NOT NULL,   -- 'TOPIC_LEARN' | 'TOPIC_REVISE' | 'SKILL' | 'PYQ_PRACTICE'
    item_id      INTEGER NOT NULL,  -- topic_id / skill_id, or exam_id for PYQ_PRACTICE
    slot_start   TEXT,
    slot_end     TEXT,
    status       TEXT DEFAULT 'PENDING'   -- DONE | CONTINUING | MISSED
);

CREATE TABLE IF NOT EXISTS settings (
    key    TEXT PRIMARY KEY,
    value  TEXT
    -- rows: skill_session_length, revision_majority_ratio (default 0.8),
    --       pyq_practice_hours (default 2, seeds exams.pyq_remaining_hours),
    --       skill_lookahead_days (default 14)
);

-- Seed defaults (idempotent-ish; adjust with INSERT OR IGNORE on SQLite)
INSERT OR IGNORE INTO settings (key, value) VALUES ('skill_session_length', '1.0');
INSERT OR IGNORE INTO settings (key, value) VALUES ('revision_majority_ratio', '0.8');
INSERT OR IGNORE INTO settings (key, value) VALUES ('pyq_practice_hours', '2');
INSERT OR IGNORE INTO settings (key, value) VALUES ('skill_lookahead_days', '14');
