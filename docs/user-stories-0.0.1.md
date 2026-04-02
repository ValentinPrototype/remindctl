# user-stories-0.0.1

**Version:** 0.0.1  
**Status:** Draft  
**Context:** User stories for `remindctl-gtd` / David productivity query layer

---

## Scope classification

### v1 core
Stories required to make David operational as a productivity specialist:
- retrieval of active projects / next actions / waiting-ons
- hierarchy-aware project diagnostics
- stale/vague/missing-next-action detection
- review-oriented outputs
- mirror-state support only insofar as it is needed for the above
- confidence / failure handling
- builder-facing boundaries needed to implement v1 cleanly

### Later / parking lot
Stories that may be useful later but are **not** required to make David useful in v1:
- rich scoreboards
- long-range execution analytics
- system observability / product telemetry
- month/year trend dashboards
- architecture ROI measurement

---

# v1 Core

## Core retrieval stories

1. **As David, I want to search reminders by the tag `active-project` and return incomplete results in JSON so that I can list current active projects reliably.**

2. **As David, I want to search reminders by the tag `next-action` and return incomplete results with title, notes, due date, and priority so that I can review actionable work.**

3. **As David, I want to search reminders by the tag `waiting-on` and createdAt older than 7 days so that I can find waiting-ons that likely need follow-up.**

4. **As David, I want to search reminders by the tag `waiting-on` and updatedAt older than 7 days so that I can distinguish neglected follow-ups from freshly touched waiting-ons.**

5. **As David, I want to search reminders by the tag `active-project` and updatedAt older than 14 days so that I can identify projects that may be stale.**

6. **As David, I want to search reminders by the tag `next-action` and dueAt earlier than now so that I can show overdue actionable tasks.**

7. **As David, I want to search reminders by the tag `next-action` and dueAt equal to today so that I can generate a today-focused action list.**

8. **As David, I want to search reminders with no due date but tagged `next-action` so that I can review floating action inventory separately from calendar pressure.**

9. **As David, I want to search reminders by list and tag together so that I can narrow productivity review to a specific list when needed.**

10. **As David, I want to search reminders by multiple tags or intersections of tag-derived result sets so that I can build more precise productivity views.**

---

## Hierarchy and project-structure stories

11. **As David, I want to retrieve parent-child reminder relationships so that I can distinguish standalone tasks from projects with subtasks.**

12. **As David, I want to show all reminders tagged `active-project` that have no subtasks so that I can detect projects that may be structurally incomplete.**

13. **As David, I want to show all reminders tagged `active-project` whose subtasks have no tags so that I can detect projects whose child tasks lack workflow meaning.**

14. **As David, I want to show all reminders tagged `active-project` whose subtasks do not include any `next-action` tag so that I can identify projects missing a clear executable next step.**

15. **As David, I want to show all parent reminders with incomplete children and a completed parent so that I can detect suspicious or inconsistent reminder states.**

16. **As David, I want to count incomplete subtasks per active project so that I can quickly compare project structure and density.**

17. **As David, I want to retrieve all child reminders for a given active project ID so that I can review whether the project has a meaningful execution structure.**

---

## Staleness and hygiene stories

18. **As David, I want to show incomplete reminders older than 7 days whose titles do not contain an obvious action verb so that I can flag likely vague tasks.**

19. **As David, I want to show active projects older than 14 days with no `next-action` child so that I can flag stale projects missing a next step.**

20. **As David, I want to show waiting-ons older than 7 days with no notes mentioning a follow-up plan so that I can flag weak waiting-on definitions.**

21. **As David, I want to show reminders tagged `next-action` that are older than 7 days and still contain only broad outcome language so that I can recommend splitting or rewriting them.**

22. **As David, I want to show all active projects with no recent child-task updates so that I can identify projects that may be drifting silently.**

23. **As David, I want to show all reminders that look like projects but are not tagged `active-project` so that I can flag likely classification mistakes.**

24. **As David, I want to show all reminders tagged `active-project` that also look like single actions so that I can flag likely over-tagging or misuse of project tags.**

25. **As David, I want to show all old incomplete reminders with empty notes so that I can identify tasks that may need more context to be actionable.**

---

## Review and planning stories

26. **As David, I want to list all active projects alongside their next actions so that I can support weekly review and project hygiene.**

27. **As David, I want to list all active projects that have no next action, no waiting-on, and no due child task so that I can highlight dead zones in the system.**

28. **As David, I want to list all next actions due today grouped by area/list so that I can support daily planning.**

29. **As David, I want to list all overdue next actions grouped by age bucket so that I can show what needs cleanup first.**

30. **As David, I want to list all waiting-ons grouped by age bucket so that I can guide follow-up review.**

31. **As David, I want to list all active projects grouped by whether they are healthy, structurally weak, or stale so that I can run a compact project-health review.**

32. **As David, I want to surface tasks that are probably blocked on missing information rather than execution discipline so that I can recommend delegation to Prometheus.**

---

## Mirror-state and sync stories

33. **As `remindctl-gtd`, I want to ingest specialized shortcut query results into a local SQLite mirror keyed by reminder ID so that multiple query families can be correlated reliably.**

34. **As `remindctl-gtd`, I want to store normalized reminders, tags, parent-child relationships, and sync metadata so that productivity diagnostics can be computed locally.**

35. **As `remindctl-gtd`, I want to track `lastSeenAt`, `lastSyncedAt`, and source path for each mirrored reminder so that David can assess data freshness.**

36. **As `remindctl-gtd`, I want to run a full initial sync into the mirror database so that later productivity queries can operate locally.**

37. **As `remindctl-gtd`, I want to run incremental syncs using trusted timestamps where possible so that repeated queries do not require expensive full re-fetches.**

38. **As `remindctl-gtd`, I want to detect reminders changed after the last successful sync so that only modified records need to be refreshed.**

39. **As `remindctl-gtd`, I want to preserve local annotations keyed by reminder ID so that David can attach productivity diagnostics without polluting reminder notes.**

40. **As `remindctl-gtd`, I want to mark mirror rows with source confidence and sync freshness so that downstream consumers can degrade gracefully when data is weak.**

---

## Reliability and failure stories

41. **As David, I want queries to return an explicit confidence level so that I do not present incomplete or unreliable reminder views as truth.**

42. **As David, I want to know when a query returned zero results because there were truly no matches versus because the shortcut/query path failed so that I do not hallucinate a clean system.**

43. **As David, I want malformed or partial shortcut payloads to be detected and rejected so that broken data does not silently corrupt the mirror database.**

44. **As David, I want the system to record which acquisition path produced each result so that I can reason about reliability when source paths disagree.**

45. **As David, I want failed or stale sync runs to be visible in the query layer so that I can lower confidence instead of giving overconfident review advice.**

---

## Implementation-boundary stories

46. **As the builder of `remindctl-gtd`, I want a clear separation between raw retrieval views and derived diagnostics so that CLI responsibilities do not blur into David’s judgment layer.**

47. **As the builder of `remindctl-gtd`, I want a stable JSON schema for reminders, tags, subtasks, and sync metadata so that David does not depend on plain-text parsing.**

48. **As the builder of `remindctl-gtd`, I want specialized shortcuts with narrow parameter contracts so that Apple Shortcuts stay maintainable and do not become a hidden programming environment.**

49. **As the builder of `remindctl-gtd`, I want productivity-specific query families documented explicitly so that future contributors understand why this project is more than a generic Reminders wrapper.**

50. **As the builder of `remindctl-gtd`, I want the system to support queries like “show all active-projects with no subtasks or with subtasks without tags” so that David can enforce project hygiene with a trustworthy local substrate.**


---

# Later / Parking Lot

## Review-cadence and execution-quality stories

51. **As David, I want to know whether a daily planning/review loop happened on a given day so that I can detect breakdowns in execution rhythm.**

52. **As David, I want to know whether a weekly review happened in the current review window so that I can proactively surface overdue reviews.**

53. **As David, I want to count how many active projects currently have a valid next action so that I can judge whether the system is trustworthy this week.**

54. **As David, I want to count how many active projects currently have no next action so that I can quantify project-hygiene debt instead of only describing it.**

55. **As David, I want to measure how many tasks older than 7 days are still vague so that I can track whether task quality is improving or degrading.**

56. **As David, I want to count how many waiting-ons are older than the follow-up threshold so that I can show external-dependency drift.**

57. **As David, I want to generate a daily execution summary showing completed next actions, carried-over next actions, and newly stale items so that I can support end-of-day review.**

58. **As David, I want to generate a weekly project-health summary so that I can show how many projects are healthy, stale, blocked, or missing next actions.**

59. **As David, I want to generate a monthly execution trend summary so that I can show whether system hygiene is improving or decaying over time.**

60. **As David, I want to generate a year-to-date execution summary so that long-term consistency can be reviewed instead of only short-term activity.**

61. **As David, I want to compare day/week/month/year execution metrics against explicit thresholds so that I can distinguish normal fluctuation from actual system drift.**

62. **As David, I want to track how often active projects are completed versus silently abandoned so that I can identify whether project selection is realistic.**

63. **As David, I want to track how often tasks are rewritten before they become actionable so that I can detect recurring task-definition failure modes.**

64. **As David, I want to track how often old vague tasks are deleted, deferred, split, or delegated so that I can measure whether review interventions are working.**

65. **As David, I want to identify projects that repeatedly appear as stale across multiple review cycles so that I can surface chronic drag instead of isolated noise.**

---

## Review workflow stories

66. **As David, I want to create a compact weekly review input set containing active projects, next actions, stale tasks, waiting-ons, and overdue items so that the review can start from a truthful snapshot.**

67. **As David, I want to show which active projects changed since the last weekly review so that the user can focus on what actually moved or did not move.**

68. **As David, I want to show which new projects became active since the last weekly review so that review scope creep is visible.**

69. **As David, I want to show which projects were completed, dropped, or deactivated since the last weekly review so that project turnover is visible.**

70. **As David, I want to show which tasks became overdue since the last review so that the user can see what decayed between check-ins.**

71. **As David, I want to show which waiting-ons crossed the follow-up threshold since the last review so that follow-up debt is visible.**

72. **As David, I want to preserve snapshots of review outputs over time so that the system can compare this week’s state to prior weeks.**

73. **As David, I want to attach a confidence level to each review snapshot so that stale or partial data does not masquerade as a trustworthy review base.**

---

## System-improvement stories

74. **As David, I want to detect recurring hygiene problems (for example: too many active projects, no next actions, vague task naming) so that I can recommend system-level improvements rather than only item-level cleanup.**

75. **As David, I want to distinguish between tool limitations and user-behavior problems so that I do not blame the workflow when the query layer is actually weak.**

76. **As David, I want to record why a result was low-confidence (for example: missing tags, stale mirror, failed shortcut, weak timestamps) so that the system can be improved intentionally.**

77. **As the builder of `remindctl-gtd`, I want to know which shortcut/query families are most frequently used so that implementation effort follows actual workflow demand.**

78. **As the builder of `remindctl-gtd`, I want to know which query families fail most often so that reliability work can be prioritized intelligently.**

79. **As the builder of `remindctl-gtd`, I want to know which fields are most often missing or unreliable in real syncs so that schema and acquisition gaps become visible.**

80. **As the builder of `remindctl-gtd`, I want to know how often David has to downgrade confidence because of mirror freshness or source issues so that sync strategy can be improved.**

81. **As the builder of `remindctl-gtd`, I want to know whether a local mirror actually reduces shortcut invocations and end-to-end query latency so that the architecture can be justified empirically.**

82. **As the builder of `remindctl-gtd`, I want to compare the mirror-based results against live-query results on a sample basis so that sync drift or mirror corruption can be detected.**

83. **As the builder of `remindctl-gtd`, I want to maintain review and execution metrics separately from reminder content so that analytics do not pollute the Apple Reminders data model.**

---

## Scoreboard / consistency stories

84. **As David, I want to compute a daily scorecard of execution quality so that the user can see whether the day was actually won, not just busy.**

85. **As David, I want to compute weekly consistency scores for planning, execution, review cadence, and project hygiene so that the user can track system trust over time.**

86. **As David, I want to compute monthly trend indicators for stale-task count, missing-next-action count, and waiting-on debt so that progress can be seen at a glance.**

87. **As David, I want to compute year-to-date system-health indicators so that long-horizon consistency can be reviewed instead of just isolated good weeks.**

88. **As David, I want to compare current scorecards to prior periods so that I can say whether execution is improving, flat, or degrading.**

89. **As David, I want to expose compact dashboard-ready metrics for day/week/month/year so that a traffic-light or scorecard view can be built later without redesigning the data model.**

90. **As David, I want to track the ratio of active projects to healthy next actions so that overload becomes measurable instead of intuitive.**
