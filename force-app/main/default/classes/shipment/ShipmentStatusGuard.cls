/**
 * A rule that must hold before a shipment may enter one of its target statuses, beyond what the
 * transition table expresses (for example: items present before Confirmed).
 *
 * Guards protect data integrity, so they apply even to users holding the status override
 * permission (architecture decision D2). Implementations must be bulk-safe and must not run SOQL
 * per change. They receive only changes the policy has already allowed.
 */
public interface ShipmentStatusGuard {
    /** Statuses this guard checks on entry. */
    Set<String> targetStatuses();

    /** Violations keyed by ShipmentStatusPolicy.StatusChange.index; changes that pass are omitted. */
    Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes);
}
