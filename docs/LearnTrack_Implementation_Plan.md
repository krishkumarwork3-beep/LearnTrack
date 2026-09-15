# LearnTrack — Final Implementation Plan
### Java + JavaFX + JDBC (no external frameworks beyond a JDBC driver)

---

## 1. Tech Stack

| Layer | Tech |
|---|---|
| UI | JavaFX — Forms, TableView, GridPane, LineChart, BarChart, ProgressBar |
| Logic | Core Java — `LocalDate`, `LocalTime`, `PriorityQueue`, `Comparator` |
| Persistence | JDBC (raw SQL, `PreparedStatement`) — no ORM |
| DB | SQLite or MySQL via JDBC |

---

## 2. Architecture

```
com.learntrack
├── model/     → Semester, WeeklyTimetableEntry, ExamPeriodRoutineEntry, DateOverride,
│                Exam, Topic, Skill, DailyLogEntry, FreeSlot, PriorityItem
├── dao/       → SemesterDAO, TimetableDAO, ExamPeriodRoutineDAO, DateOverrideDAO,
│                ExamDAO, TopicDAO, SkillDAO, DailyLogDAO
├── service/   → FreeSlotService, ExamPeriodFreeSlotService, ScoringService,
│                PriorityQueueService, SemesterReplanService, SemesterService
├── ui/
│   ├── setup/   → TimetableSetupWizard, ExamPeriodRoutineWizard
│   ├── forms/   → ExamFormController, TopicFormController, SkillFormController
│   ├── views/   → DashboardView (slot timetable), CalendarGridView, SkillDashboardView, ExamPeriodView
│   ├── charts/  → DecayChartView, FeasibilityBarView
│   └── MainApp.java
└── util/      → DBConnection, DateUtils
```

---

## 3. Database Schema (final)

```sql
CREATE TABLE semesters (
    semester_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    status        TEXT DEFAULT 'ACTIVE'
);

-- Recurring weekly commitments for NORMAL teaching days. Entered once per semester.
-- Also used for MST/EST topics BEFORE a datesheet exists (see section 4).
CREATE TABLE weekly_timetable (
    entry_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    semester_id     INTEGER NOT NULL,
    day_of_week     TEXT NOT NULL,      -- MONDAY..SUNDAY
    start_time      TEXT NOT NULL,
    end_time        TEXT NOT NULL,
    activity_type   TEXT NOT NULL,      -- CLASS | LAB | MEAL | SLEEP | OTHER
    label           TEXT,
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

CREATE TABLE weekday_study_preference (
    semester_id   INTEGER NOT NULL,
    day_of_week   TEXT NOT NULL,
    study_hours   REAL NOT NULL,
    PRIMARY KEY (semester_id, day_of_week),
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

-- Simplified fixed routine used ONLY once a real MST/EST datesheet exists.
-- Entered once, applies to every day inside the resulting exam window.
CREATE TABLE exam_period_routine (
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
CREATE TABLE date_overrides (
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
-- negotiation loop and the important_flag reset (sections 4, 9). A semester
-- typically has at most one MST batch and one EST batch.
CREATE TABLE exams (
    exam_id              INTEGER PRIMARY KEY AUTOINCREMENT,
    semester_id           INTEGER NOT NULL,
    subject               TEXT NOT NULL,
    exam_type             TEXT NOT NULL,   -- 'NORMAL' | 'MST' | 'EST'
    credits               INTEGER DEFAULT 1,   -- entered upfront for EVERY exam type
    eval_marks             REAL DEFAULT 0,      -- entered upfront for EVERY exam type
    exam_date             TEXT,             -- exact date; NULL until datesheet released (MST/EST only)
    exam_start_time        TEXT,             -- NULL until known (see section 4)
    exam_end_time          TEXT,
    travel_time_minutes    INTEGER DEFAULT 30,
    window_start_date      TEXT,             -- provisional, MST/EST only — doubles as the effective
                                              -- deadline for ALL of this exam's topics until a real
                                              -- exam_date is entered (section 4)
    window_end_date        TEXT,
    pyq_remaining_hours    REAL DEFAULT 2,   -- see section 5a; counts down like a topic's remaining_hours
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

CREATE TABLE topics (
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
    last_revised                TEXT,                 -- only updated when a revision cycle is CLOSED (section 10)
    important_flag             INTEGER DEFAULT 1,     -- 0 = temporarily excluded from the queue during an
                                                        -- active MST/EST negotiation (see section 5 and 9)
    FOREIGN KEY (exam_id) REFERENCES exams(exam_id)
);

CREATE TABLE skills (
    skill_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name             TEXT NOT NULL,
    category         TEXT NOT NULL,
    proficiency      INTEGER NOT NULL,
    last_practiced   TEXT NOT NULL
    -- no semester_id: never deleted on semester rollover, tracked forever
);

CREATE TABLE daily_log (
    log_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    log_date     TEXT NOT NULL,
    item_type    TEXT NOT NULL,   -- 'TOPIC_LEARN' | 'TOPIC_REVISE' | 'SKILL' | 'PYQ_PRACTICE'
    item_id      INTEGER NOT NULL,  -- topic_id / skill_id, or exam_id for PYQ_PRACTICE
    slot_start   TEXT,
    slot_end     TEXT,
    status       TEXT DEFAULT 'PENDING'   -- DONE | CONTINUING | MISSED
);

CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT
    -- rows: skill_session_length, revision_majority_ratio (default 0.8),
    --       pyq_practice_hours (default 2, seeds exams.pyq_remaining_hours),
    --       skill_lookahead_days (default 14)
);
```

---

## 4. Two Modes for MST/EST — Which One Applies, and When

**Batch definition:** all exams sharing the same `exam_type` (`'MST'` or `'EST'`) within the active semester form one batch. A semester typically has one MST batch and one EST batch, each planned/negotiated as a unit.

**Before a datesheet exists:** an MST/EST exam behaves exactly like a NORMAL topic set. `window_start_date` is not a fallback estimate — it **is** the effective deadline used for every topic under that exam, feeding `debtScore`/`revisionScore` the same way a real `exam_date` would. These topics are scheduled through the ordinary `FreeSlotService` (weekly timetable + `weekday_study_preference`), spread across the remaining semester like any other topic. No `exam_period_routine`, no buffers, no negotiation loop, no exam-day blocking — nothing date-specific happens on `window_start_date` itself; it only shapes urgency.

**Credits and `eval_marks` are entered upfront for every exam, regardless of type** — they're properties of the subject/evaluation itself, not tied to knowing the exact date. Only `exam_date`, `exam_start_time`, `exam_end_time`, and `travel_time_minutes` are deferred for MST/EST until the datesheet exists.

**The moment a real `exam_date` (and `exam_start_time`/`exam_end_time`) is entered** for an exam in a batch, that exam switches to the special engine:
- Its topics' deadline becomes the real `exam_date`.
- `ExamPeriodFreeSlotService` takes over for the span from today through the latest known `exam_date` across that batch, using `exam_period_routine` instead of the weekly timetable.
- The negotiation loop (section 9) and exam-time buffers (below) become active for that batch.
- `regenerateSemesterPlan` runs immediately to replan around the real date.

Different subjects in the same batch can have their datesheets entered at different times — each exam switches over independently the moment its own real date is known.

**Free-slot computation once an exam has a real date (`ExamPeriodFreeSlotService`):**
```
fixedBlocks(date) = exam_period_routine (meals, sleep, other)
                     + for each dated exam sitting on `date`:
                         [exam_start_time - travel_time_minutes, exam_end_time + 1h]
freeSlots(date) = complement of fixedBlocks(date) within 24h   -- a list of time intervals
```
The block **before** an exam is only the actual travel/prep time (`travel_time_minutes`) — study can continue right up until the student needs to leave. The block **after** is a flat 1-hour buffer, after which the next exam's preparation can resume. Meal/sleep/other blocks still apply throughout.

**This same asymmetric buffer rule applies to NORMAL exams too** (section 8) — one buffer definition used everywhere.

**A NORMAL exam whose date falls inside a dated MST/EST window** uses `ExamPeriodFreeSlotService` for that date, and any same-day clash uses the weightage split in section 8 regardless of exam type.

---

## 5. Scoring Formulas

```
debtScore      = (importance * difficulty * remaining_hours) / max(daysLeft, 1)
revisionScore  = (importance * daysSinceRevision * revision_remaining_hours) / revision_interval_days
decayScore     = daysBetween(last_practiced, today) / (proficiency + 1)
```
`daysLeft = daysBetween(today, effectiveDeadline(E))`, where:
```
effectiveDeadline(E):
    if E.exam_date is set:              return E.exam_date
    if today <= E.window_start_date:    return E.window_start_date
    if today <= E.window_end_date:      return E.window_end_date   -- datesheet still not out once the
                                                                     -- rough window's start has already
                                                                     -- passed; fall back to the window's
                                                                     -- end instead of a stale past date
    return today                        -- the whole window has lapsed with no datesheet at all;
                                          -- treat it as due right now (daysLeft floors to 1 below,
                                          -- so it stays maximally urgent rather than dropping out)
```
An exam counts as **unfinished** (and so keeps contributing to the horizon in section 6, and keeps its topics in the queue) as long as `exam_date` is unset, or `exam_date >= today` — it never drops out of scheduling just because `window_start_date` or `window_end_date` has passed while still awaiting a real datesheet; only a real, past `exam_date` marks it finished.

A topic's `revisionScore` only enters the queue once `daysSinceRevision >= revision_interval_days`, and only while the exam is still unfinished.

**Queue membership is filtered before scoring:** `PriorityQueueService.build()` only includes a topic if `important_flag = 1`. Topics temporarily excluded during an active batch's negotiation (section 9) are skipped entirely — they contribute no score and receive no time until the flag is reset. All included topics, all skills, and all eligible PYQ items (5a) normalize into one shared `PriorityQueue<PriorityItem>`.

### 5a. PYQ Practice — a single unified rule, no special day

One `examWeight` formula, used everywhere in this document (section 8 included):
```
examWeight(E) = credits(E) * max(eval_marks(E), 1)   -- the floor of 1 avoids a zero weight
                                                       -- when eval_marks hasn't been set to anything
                                                       -- meaningful yet, so shares never divide by zero
```

```
pyqEligible(E) = every topic under E (with important_flag = 1) has remaining_hours == 0
                 AND E.pyq_remaining_hours > 0
                 AND today <= effectiveDeadline(E)

pyqScore(E) = (examWeight(E) * E.pyq_remaining_hours) / max(daysLeft, 1)     -- only computed if pyqEligible(E)
```
Once eligible, `PYQ_PRACTICE` for that exam is just another `PriorityItem` competing normally in the queue — no reserved block, no fixed "day before," no separate carve-out logic. It surfaces naturally as the exam approaches, and only after every currently-in-scope topic under that exam is covered — "finish the syllabus first, then work in PYQs."

---

## 6. Whole-Semester Replanning — the single unifying mechanism

```
function regenerateSemesterPlan(fromDate):
    -- 1. Lock history: daily_log rows before fromDate are never touched
    -- 2. Clear the future: delete daily_log rows on/after fromDate with status PENDING/CONTINUING
    -- 3. Rebuild the priority queue from current state, honoring important_flag (section 5)
    queue = PriorityQueueService.build(activeSemesterTopics, allSkills, eligiblePyqItems)

    -- 4. Determine how far forward to plan:
    lastDeadline = latest effectiveDeadline(E) (section 5) among all unfinished exams
                   -- "unfinished" per section 5's definition — an MST/EST exam whose window has
                   -- lapsed without a datesheet is still unfinished, so it still counts here
    horizon = any unfinished exams exist
              ? lastDeadline
              : today + settings.skill_lookahead_days

    -- 5. Walk every day from fromDate to horizon, filling it
    for date = fromDate to horizon:
        if date falls within a DATED MST/EST window:
            freeSlots = ExamPeriodFreeSlotService.computeFreeSlots(date)
        else:
            freeSlots = FreeSlotService.computeFreeSlots(date)
            if date == someExam.examDate - 1: apply exam-eve revision-majority rule (section 8, NORMAL only)

        schedule = fillDay(freeSlots, studyBudget(date), queue)   -- section 7
        persist schedule into daily_log for date

    -- 6. If a dated batch's window just closed, reset important_flag = 1
    --    for every topic under that batch's exams (section 9)
```

**Called after every one of these events:**
- Done/Not-yet dialog answered (topic, skill, or PYQ)
- A class/lab cancelled
- A datesheet entered/updated (mode switch, section 4)
- An "important topics" selection changes during negotiation
- **Every time the app is opened** — unconditionally, not only when a missed day is detected, so the rolling `skill_lookahead_days` horizon keeps extending even during stretches with no exams left and nothing logged.

---

## 7. Slot-Filling Within a Single Day

```
function fillDay(freeSlots, studyBudget, queue):
    schedule = []
    for slot in freeSlots (chronological order):
        remainingSlot = slot.duration
        while remainingSlot > 0 and studyBudget > 0 and queue not empty:
            item  = queue.poll()
            cap   = item.isSkill ? SKILL_SESSION_LENGTH : MAX_SESSION_TOPIC
            alloc = min(item.remaining, remainingSlot, cap, studyBudget)
            if alloc <= 0: break
            schedule.add(item, slotStart, slotStart + alloc)
            remainingSlot -= alloc; studyBudget -= alloc
            if item still has remaining: re-push with reduced remaining
    return schedule
```
The student can edit today's generated timetable directly — treated as a manual override layered on top of the next `regenerateSemesterPlan` call, not a permanent divergence.

---

## 8. NORMAL Exams — Weightage-Based Same-Day Split

Uses the single `examWeight` formula from section 5a:
```
share(E)          = examWeight(E) / sum(examWeight over all same-day exams)
totalFreeTime(date) = sum of the durations of freeSlots(date)   -- freeSlots is a list of intervals;
                                                                   -- this is its total duration
hoursForExam(E)   = totalFreeTime(date) * share(E)
```
Example: (5 credits × 3 marks = 15) vs (3 credits × 15 marks = 45) → the second exam gets 3× the share, even with fewer credits.

**Day before a NORMAL quiz — including when more than one exam shares that eve:**
```
examsWithEveToday = all NORMAL exams where exam_date == date + 1

if examsWithEveToday is empty:
    -- no eve treatment; this is an ordinary day, use fillDay() directly (section 7)
else:
    totalWeight        = sum(examWeight(E) for E in examsWithEveToday)
    revisionBudgetTotal = totalFreeTime(date) * settings.revision_majority_ratio   -- default 0.8
    leftoverBudget      = totalFreeTime(date) - revisionBudgetTotal

    for E in examsWithEveToday:
        share(E)          = examWeight(E) / totalWeight
        revisionBudget(E) = revisionBudgetTotal * share(E)
        fill revisionBudget(E) with E's topics (ranked by score), then E's PYQ item if eligible (section 5a)

    fill leftoverBudget from the general priority queue (this also covers any exam
    NOT in examsWithEveToday, so nothing else in the semester goes untouched that day)
```
This reuses the same `examWeight`/`share` mechanism as the same-day split above — a single exam sharing the eve alone simply gets `share(E) = 1`, so the single-exam case is just this formula's trivial case, not a separate rule.

**Exam day itself:** the exam's time block is excluded via `date_overrides`, using the asymmetric buffer from section 4 — only `travel_time_minutes` blocked beforehand, a flat 1-hour buffer afterward.

---

## 9. MST / EST — Once Dated (Negotiation Loop)

- Applies only after a real `exam_date` is entered for exams in a batch (section 4).
- Free time comes purely from `exam_period_routine` + each dated exam's block-with-buffer.
- If total required hours (topics with `important_flag = 1`, plus eligible PYQ items) exceed the window's real capacity:
```
while requiredHours > availableHours:
    ask "increase daily study hours by X?" -> yes: raise capacity for those dates, recompute
                                            -> no: ask to pick important topics
                                                   -> important_flag = 0 for excluded topics (section 5)
                                                   -> recompute requiredHours from only important_flag = 1 topics
```
- **Once the batch's window closes** (today passes the last dated exam in that batch): `regenerateSemesterPlan` resets `important_flag = 1` for every topic under that batch — anything trimmed during the crunch automatically re-enters normal scoring afterward.

---

## 10. Progress Logging (Done / Not-yet) — per item type

**Topic, LEARNING phase:**
- **Yes, done** → `remaining_hours = 0`, `phase = REVISION`, `revision_remaining_hours = revision_hours_needed`, `last_revised = today`.
- **Not yet** → student enters a new estimate, overwriting `remaining_hours`.

**Topic, REVISION phase:**
- **Yes, done** (cycle closed) → `last_revised = today`, `revision_remaining_hours` resets to `revision_hours_needed` for the next cycle. No terminal state — it keeps recurring until its deadline passes.
- **Not yet** (cycle stays open) → student enters a new estimate, overwriting `revision_remaining_hours`; `last_revised` is **not** updated, so it stays overdue.

**Skill:** logging a session — of any length — updates `last_practiced = today`. Decay tracking is a "did you touch it today" signal, not an hours-tracked total, so there is no partial/incomplete state to worry about.

**PYQ_PRACTICE** (behaves exactly like a topic in LEARNING phase, using `pyq_remaining_hours`):
- **Yes, done** → `pyq_remaining_hours = 0`.
- **Not yet** → student enters a new estimate, overwriting `pyq_remaining_hours`.

Any of these calls `regenerateSemesterPlan(today)` (section 6).

---

## 11. Class/Lab Cancellation

```
function handleCancellation(date, timetableEntryId):
    insert date_overrides(date, timetableEntryId, action='CANCEL')
    regenerateSemesterPlan(date)
```

---

## 12. Semester Lifecycle — Deletion, Not Archiving

```
function startNewSemester(newName):
    DELETE daily_log rows for TOPIC_LEARN / TOPIC_REVISE / PYQ_PRACTICE tied to old semester
    DELETE topics, exams, weekly_timetable, weekday_study_preference, exam_period_routine
           for the old semester_id
    remove old semesters row; insert new one, status = ACTIVE
    -- prompts TimetableSetupWizard again; Exam Period Routine Wizard is entered later,
    -- only once a datesheet for that semester's first MST/EST batch actually arrives
```
`skills` and any `daily_log` rows of type `'SKILL'` are never touched — permanent, semester-independent.

---

## 13. Feasibility Bar (NORMAL exam backlog)

```
for topic in topics sorted by exam_date ascending:
    cumulativeNeeded += topic.remaining_hours
    cumulativeCapacity += sum(real per-day study capacity up to exam_date)
    if cumulativeNeeded > cumulativeCapacity: infeasible
```

---

## 14. UI Screens

| Screen | Control(s) | Purpose |
|---|---|---|
| Timetable Setup Wizard | Forms | Weekly classes/labs/meals/sleep + weekday study-hour preference |
| Exam Period Routine Wizard | Forms | Meals/sleep/other routine, entered once the first MST/EST batch in the semester gets a datesheet |
| Dashboard (Today) | Slot-based timetable + ProgressBar | Suggested schedule, editable, Done/Not-yet dialog (topic/skill/PYQ), feasibility bar |
| Exams | Forms + TableView | Type, credits, eval marks entered upfront for every exam; date/start/end time/travel time added once known |
| Topics | Forms + TableView | Topics per exam incl. revision fields |
| Skills | Forms + TableView + Chart | Permanent, semester-independent |
| Calendar | GridPane | Full semester view, regenerated after every relevant event |
| Exam Period Planner | Forms + TableView | Negotiation loop, important-topics selection (post-datesheet only) |
| Settings | Forms | Skill session length, revision majority ratio, PYQ practice hours, skill lookahead days, semester management |

---

## 15. Build Phases

1. Skeleton + DB init + models
2. DAO layer (full CRUD, incl. DateOverrideDAO)
3. Timetable Setup Wizard + FreeSlotService (Exam Period Routine Wizard deferred until first datesheet)
4. Exam/Topic/Skill forms — credits/eval marks always collected; date/time/travel-time fields unlock once known
5. Scoring services + unified priority queue, filtered by `important_flag`, incl. PYQ eligibility gate
6. `regenerateSemesterPlan` (rolling horizon, runs on every app open) + `fillDay`
7. Dashboard + Calendar views
8. Done/Not-yet dialog, all four item-type variants
9. Cancellation handling
10. Weightage-based same-day exam split (single `examWeight` formula, section 5a/8)
11. Datesheet-entry mode switch (weekly-timetable → exam-period engine) + negotiation loop + `important_flag` reset on batch close
12. Semester lifecycle (delete-on-rollover, skills excluded)
13. Charts + feasibility bar
14. Edge cases + polish

---

## 16. Edge Cases

- `daysLeft = 0` → floor at 1.
- Skill never practiced → max decay, prompt for an initial date.
- Two exams with overlapping buffer windows same day → merge into one blocked interval.
- A topic marked "Yes, done" mid-morning → regeneration still runs for the rest of today onward.
- Datesheet released mid-negotiation → re-run feasibility immediately.
- Semester deletion with unfinished topics → warn clearly before deleting; it's permanent.
- A NORMAL exam lands inside a dated MST/EST window → uses `ExamPeriodFreeSlotService` for that date.
- All exams in a semester finish but the semester hasn't been manually rolled over → rolling horizon keeps generating skill-only days, refreshed on every app open.
- A datesheet is released for only some subjects in a batch → each dated exam switches to the special engine independently; undated ones keep using `window_start_date` until their own date lands.
- `eval_marks` left at its default of 0 for an exam → `examWeight` still resolves to at least `credits(E) * 1`, so same-day splits and PYQ scoring never divide by zero.
- Two or more NORMAL exams share the same eve date → the 80% revision-majority budget is split across them by `examWeight`, not handed entirely to one (section 8).
- An MST/EST window's `window_start_date` (or even `window_end_date`) passes with no datesheet yet → `effectiveDeadline` rolls forward instead of going stale, and the exam still counts as unfinished, so it never silently drops out of the schedule or the horizon calculation (section 5).
