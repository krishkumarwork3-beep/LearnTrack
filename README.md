# LearnTrack

Exam-backlog + skill-decay planner. Java 17 + JavaFX + JDBC (SQLite), no ORM, no
external scheduling frameworks — everything is built from `LearnTrack_Implementation_Plan.md`.

This is a **scaffold**: every class exists with the right name, package, and a
doc-comment pointing at the exact plan section it implements, but no logic yet.
Build order follows the plan's own section 15 ("Build Phases") — implement
`model/` and `dao/` first, then `service/`, then wire up `ui/`.

## Folder structure

```
learntrack/
├── pom.xml                          Maven build, JavaFX + sqlite-jdbc + JUnit 5
├── README.md
└── src/
    ├── main/
    │   ├── java/com/learntrack/
    │   │   ├── MainApp.java         Entry point (JavaFX Application)
    │   │   │
    │   │   ├── model/               Plain data classes — one per DB table / value object
    │   │   │   ├── Semester.java
    │   │   │   ├── WeeklyTimetableEntry.java
    │   │   │   ├── WeekdayStudyPreference.java
    │   │   │   ├── ExamPeriodRoutineEntry.java
    │   │   │   ├── DateOverride.java
    │   │   │   ├── Exam.java
    │   │   │   ├── Topic.java
    │   │   │   ├── Skill.java
    │   │   │   ├── DailyLogEntry.java
    │   │   │   ├── FreeSlot.java            (start/end time interval, not a DB table)
    │   │   │   └── PriorityItem.java        (queue wrapper: topic/skill/PYQ + score)
    │   │   │
    │   │   ├── dao/                 JDBC CRUD, one class per table (raw SQL, PreparedStatement)
    │   │   │   ├── SemesterDAO.java
    │   │   │   ├── TimetableDAO.java
    │   │   │   ├── ExamPeriodRoutineDAO.java
    │   │   │   ├── DateOverrideDAO.java
    │   │   │   ├── ExamDAO.java
    │   │   │   ├── TopicDAO.java
    │   │   │   ├── SkillDAO.java             (never touched by semester rollover)
    │   │   │   └── DailyLogDAO.java
    │   │   │
    │   │   ├── service/             All business logic — the actual planning engine
    │   │   │   ├── FreeSlotService.java             plan §4  (normal-day free time)
    │   │   │   ├── ExamPeriodFreeSlotService.java   plan §4  (dated MST/EST free time)
    │   │   │   ├── ScoringService.java              plan §5  (debt/revision/decay/PYQ scores)
    │   │   │   ├── PriorityQueueService.java        plan §5  (queue build + important_flag filter)
    │   │   │   ├── SemesterReplanService.java       plan §6-9 (the core replanning engine)
    │   │   │   └── SemesterService.java             plan §12 (start new semester / delete old)
    │   │   │
    │   │   ├── ui/
    │   │   │   ├── setup/
    │   │   │   │   ├── TimetableSetupWizard.java
    │   │   │   │   └── ExamPeriodRoutineWizard.java  (shown once the first datesheet lands)
    │   │   │   ├── forms/
    │   │   │   │   ├── ExamFormController.java
    │   │   │   │   ├── TopicFormController.java
    │   │   │   │   └── SkillFormController.java
    │   │   │   ├── views/
    │   │   │   │   ├── DashboardView.java            today's slot timetable + Done/Not-yet dialogs
    │   │   │   │   ├── CalendarGridView.java         full semester GridPane view
    │   │   │   │   ├── SkillDashboardView.java       TableView sorted by decayScore
    │   │   │   │   └── ExamPeriodView.java           negotiation loop UI
    │   │   │   └── charts/
    │   │   │       ├── DecayChartView.java
    │   │   │       └── FeasibilityBarView.java
    │   │   │
    │   │   └── util/
    │   │       ├── DBConnection.java
    │   │       └── DateUtils.java
    │   │
    │   └── resources/
    │       ├── application.properties
    │       └── db/
    │           └── schema.sql        Full schema, copied verbatim from the plan (§3)
    │
    └── test/java/com/learntrack/
        ├── service/
        │   ├── ScoringServiceTest.java
        │   ├── PriorityQueueServiceTest.java
        │   └── SemesterReplanServiceTest.java
        └── dao/                      (add DAO tests here as each DAO is implemented)
```

## Where to start

1. `model/` — fill in fields matching `schema.sql` exactly.
2. `dao/` — CRUD per table; `DailyLogDAO` also needs the "lock past / clear pending future" queries from plan §6.
3. `service/ScoringService` and `PriorityQueueService` — pure logic, easiest to unit test first.
4. `service/SemesterReplanService` — the heart of the app; implement `regenerateSemesterPlan` and `fillDay` per plan §6-7, then the eve-day split (§8) and negotiation loop (§9).
5. `ui/` — wire views to the services last, once the engine is tested standalone.

## Reference docs

- `LearnTrack_Implementation_Plan.md` — the full design this scaffold is generated from.
- `LearnTrack_User_Guide.md` — the user-facing behavior every service method should ultimately produce.
