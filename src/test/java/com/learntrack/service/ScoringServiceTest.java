package com.learntrack.service;

/**
 * Tests for ScoringService.
 * Implementation Plan reference: section 5 (debtScore, revisionScore, decayScore, pyqScore).
 *
 * Suggested cases:
 *  - debtScore rises as remaining_hours grows or daysLeft shrinks
 *  - daysLeft floors at 1 (never divides by zero)
 *  - effectiveDeadline() fallback chain: exam_date -> window_start_date -> window_end_date -> today
 *  - revisionScore only activates once daysSinceRevision >= revision_interval_days
 *  - pyqEligible() is false until every in-scope topic's remaining_hours == 0
 */
public class ScoringServiceTest {
}
