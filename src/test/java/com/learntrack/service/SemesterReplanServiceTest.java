package com.learntrack.service;

/**
 * Tests for SemesterReplanService.
 * Implementation Plan reference: section 6 (regenerateSemesterPlan), section 7 (fillDay),
 * section 8 (same-day / eve-day weightage split), section 9 (negotiation loop).
 *
 * Suggested cases:
 *  - history before fromDate is never modified
 *  - finishing a topic early frees capacity on later days, not just the next day
 *  - two same-day NORMAL exams split available time by examWeight
 *  - two exams sharing an eve date split the revision-majority budget by examWeight
 *  - rolling horizon extends via skill_lookahead_days once no exams remain
 *  - a datesheet entered mid-semester switches that exam to ExamPeriodFreeSlotService
 */
public class SemesterReplanServiceTest {
}
