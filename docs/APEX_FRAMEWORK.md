# eLogix ERP - Apex Framework

| | |
|---|---|
| Status | Live since Phase 2 (deploy `0Afg700000KNnfeCAD`, 2026-11-19) |
| Contract | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) sections 4 and 6.1 |
| Source | `force-app/main/default/classes/base/`, `classes/common/`, `classes/selectors/`, `classes/handlers/` |

This is the lightweight in-house replacement for fflib (decision D10 in [SOLUTION_ARCHITECTURE.md](SOLUTION_ARCHITECTURE.md)). Every later module builds on it.

## 1. Classes

| Class | Folder | Sharing | Purpose |
|---|---|---|---|
| `TriggerHandler` | base | inherited | Virtual base. `run()` dispatches on `Trigger.operationType` to `beforeInsert` … `afterUndelete`. Context is held in `newList` and `oldMap`, and a `@TestVisible` constructor lets tests inject it. |
| `ELogixException` | base | n/a | Virtual base exception. `code` is a stable reason code, set with `withCode()`. The message is a Custom Label. |
| `ValidationException`, `ConfigurationException`, `AuthorizationException` | base | n/a | Typed failures. `AuthorizationException.ACCESS_DENIED` is the shared code. |
| `ServiceResult` | base | inherited | Per-request results for partial-success services: `isSuccess`, `errors` (`code`, `message`, `recordIndex`, `recordId`), `recordIds`, `errorsFor(index)`. `@AuraEnabled`, ready for LWCs. |
| `Logger` | common | inherited | `debug`/`info`/`warn`/`error` to the debug log, prefixed `[eLogix][<request id>][<context>]`. |
| `ExceptionHandler` | common | inherited | `toUserMessage(e, context)`: logs the exception. eLogix exceptions keep their label message. Anything else becomes `eLogix_Unexpected_Error` with the request id as a support reference. |
| `PermissionService` | common | inherited | `hasPermission(name)` wraps `FeatureManagement.checkPermission`. Never throws; blank or unknown names are false. |
| `SettingsService` | common | inherited | `getNumber`/`getText`/`getBoolean` over `eLogix_Setting__mdt.getInstance()`. A missing record or empty value throws `ConfigurationException` (`SETTING_MISSING`). |
| `ShipmentSelector`, `TrackingEventSelector` | selectors | inherited | All SOQL for those objects. User mode, unless a documented exception applies ([APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) section 6.1). |
| `ShipmentTriggerHandler` | handlers | with | Routes shipment trigger contexts to `ShipmentDomain` (before) and `TrackingService` (after). |

## 2. Conventions every module follows

1. **One trigger per object.** The trigger body is `new <Object>TriggerHandler().run();`. Handlers contain no business rules.
2. **No recursion flags and no bypass switch.** Handlers are stateless. A re-fired trigger is evaluated again from `Trigger.old` and `Trigger.new`. Duplicate side effects are prevented by deterministic keys checked in the database, never by static "already ran" sets. Static sets break partial-success retries, because the platform re-runs triggers after rollback without resetting statics.
3. **Errors.** Trigger code reports business failures with `record.Field__c.addError(label)` and never throws. Services return `ServiceResult` for per-record failures and throw `ELogixException` subclasses only for whole-operation failures: missing configuration, or no object access.
4. **Messages.** Every user-facing Apex message is a Custom Label in `labels/CustomLabels.labels-meta.xml`, which is hand-maintained (the generator does not own it). Placeholders use `String.format` (`{0}`). Label text must not contain apostrophes, because `String.format` treats `'` as an escape.
5. **Logging.** Log Ids, reason codes, counts and correlation ids, never field values or payloads. `Logger.error` logs only an exception's type, eLogix code and stack trace, because platform messages can include record data.
6. **Sharing and access.**
   - Classes declare `with sharing`, or `inherited sharing` for utilities and selectors.
   - `without sharing` appears only in private inner classes with a written justification.
   - User-mode SOQL and DML (`WITH USER_MODE`, `AccessLevel.USER_MODE`) are the default for user-initiated reads and writes.
   - System mode is used only to write protected fields, after the owning service has authorized the caller.
7. **Configuration.** Business thresholds come from `eLogix_Setting__mdt` through `SettingsService`, and lifecycle rules from `Shipment_Status_Transition__mdt`. Missing configuration fails closed.
8. **Test seams** are `@TestVisible private` and limited to:
   - `PermissionService.testOverrides`
   - `SettingsService.testOverrides`
   - `TrackingService.nowOverride` (clock)
   - injectable constructors on policy, domain, service and handler

   Production code has no "fail on purpose" switches.

## 3. Adding a trigger for a new object (template)

```apex
trigger VehicleAssignmentTrigger on Vehicle_Assignment__c(before insert, before update, after insert, after update) {
    new VehicleAssignmentTriggerHandler().run();
}

public with sharing class VehicleAssignmentTriggerHandler extends TriggerHandler {
    public VehicleAssignmentTriggerHandler() { super(); }
    @TestVisible
    private VehicleAssignmentTriggerHandler(System.TriggerOperation op, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(op, newList, oldMap);
    }
    protected override void beforeInsert() { new FleetAllocationPolicy().validate((List<Vehicle_Assignment__c>) newList); }
}
```

Add a `<Object>TriggerHandlerTest` that runs as a role user created with `TestDataFactory.createUser`.

## 4. Test support

`TestDataFactory` (`classes/test/`) provides:
- a business unit and customer that satisfy the deployed validation rules;
- shipments and items, plus `advance()` to walk allowed transitions;
- role users on the **Standard Platform User** profile with real permission-set assignments. The org has 6 free Salesforce Platform licenses but only 2 free Salesforce licenses;
- `shipmentInMemory()`, which sets read-only fields such as roll-ups through JSON for pure unit tests;
- `fakeId()`.

The deploying admin holds every eLogix custom permission, so tests that depend on permissions always run as a role user.
