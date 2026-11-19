/**
 * Base class for every eLogix trigger handler.
 *
 * A trigger creates its handler and calls run(); run() dispatches on the trigger operation to the
 * matching virtual method. Handlers read the trigger context through newList and oldMap rather
 * than Trigger.*, so they can be unit tested without DML through the protected constructor.
 *
 * Deliberately absent: recursion flags and a bypass switch. eLogix handlers are stateless, so a
 * re-fired trigger (workflow field update, partial-success retry) is evaluated again from
 * Trigger.old and Trigger.new. A bypass API would let any Apex skip business policy.
 * See docs/APEX_ARCHITECTURE.md section 4.1.
 */
public inherited sharing virtual class TriggerHandler {
    protected System.TriggerOperation operation;
    protected List<SObject> newList;
    protected Map<Id, SObject> oldMap;

    public TriggerHandler() {
        this(Trigger.operationType, Trigger.new, Trigger.oldMap);
    }

    @TestVisible
    protected TriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        this.operation = operation;
        this.newList = newList == null ? new List<SObject>() : newList;
        this.oldMap = oldMap == null ? new Map<Id, SObject>() : oldMap;
    }

    public void run() {
        if (operation == null) {
            throw new ELogixException('TriggerHandler.run() must be called from a trigger context.').withCode('NOT_IN_TRIGGER');
        }
        switch on operation {
            when BEFORE_INSERT {
                beforeInsert();
            }
            when BEFORE_UPDATE {
                beforeUpdate();
            }
            when BEFORE_DELETE {
                beforeDelete();
            }
            when AFTER_INSERT {
                afterInsert();
            }
            when AFTER_UPDATE {
                afterUpdate();
            }
            when AFTER_DELETE {
                afterDelete();
            }
            when AFTER_UNDELETE {
                afterUndelete();
            }
        }
    }

    protected virtual void beforeInsert() {
    }
    protected virtual void beforeUpdate() {
    }
    protected virtual void beforeDelete() {
    }
    protected virtual void afterInsert() {
    }
    protected virtual void afterUpdate() {
    }
    protected virtual void afterDelete() {
    }
    protected virtual void afterUndelete() {
    }
}
