/**
 * Assignment windows in the org time zone (decision Q3): from the pickup date at 00:00:00 to the
 * expected delivery date at 23:59:59. Every overlap check in Phase 4 uses these boundaries, so two
 * bookings on consecutive days never overlap and two bookings sharing a day always do.
 */
public inherited sharing class AssignmentWindow {
    /** Org configuration, read once per transaction. */
    private static Timezone orgTimeZone;

    public static Datetime startOf(Date day) {
        return atOrgTime(day, Time.newInstance(0, 0, 0, 0));
    }

    public static Datetime endOf(Date day) {
        return atOrgTime(day, Time.newInstance(23, 59, 59, 0));
    }

    /** Datetime windows overlap when each starts before the other ends. A blank end means open-ended. */
    public static Boolean overlaps(Datetime startA, Datetime endA, Datetime startB, Datetime endB) {
        return (endB == null || startA < endB) && (endA == null || startB < endA);
    }

    /** Inclusive date ranges overlap when each starts on or before the other ends. A blank end means open-ended. */
    public static Boolean overlapsDays(Date startA, Date endA, Date startB, Date endB) {
        return (endB == null || startA <= endB) && (endA == null || startB <= endA);
    }

    @TestVisible
    private static Timezone orgTimeZone() {
        if (orgTimeZone == null) {
            orgTimeZone = Timezone.getTimeZone([SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey);
        }
        return orgTimeZone;
    }

    private static Datetime atOrgTime(Date day, Time timeOfDay) {
        Datetime asGmt = Datetime.newInstanceGmt(day, timeOfDay);
        Integer offsetMillis = orgTimeZone().getOffset(asGmt);
        return asGmt.addSeconds(-offsetMillis / 1000);
    }
}
