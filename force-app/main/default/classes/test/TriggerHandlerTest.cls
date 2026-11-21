@IsTest
private class TriggerHandlerTest {
    private class RecordingHandler extends TriggerHandler {
        public List<String> calls = new List<String>();

        public RecordingHandler(System.TriggerOperation operation) {
            super(operation, null, null);
        }

        protected override void beforeInsert() {
            calls.add('beforeInsert');
        }
        protected override void beforeUpdate() {
            calls.add('beforeUpdate');
        }
        protected override void beforeDelete() {
            calls.add('beforeDelete');
        }
        protected override void afterInsert() {
            calls.add('afterInsert');
        }
        protected override void afterUpdate() {
            calls.add('afterUpdate');
        }
        protected override void afterDelete() {
            calls.add('afterDelete');
        }
        protected override void afterUndelete() {
            calls.add('afterUndelete');
            Assert.isTrue(newList.isEmpty(), 'Null context lists are replaced by empty collections.');
            Assert.isTrue(oldMap.isEmpty());
        }
    }

    /** A handler that overrides nothing: every operation is a safe no-op. */
    private class EmptyHandler extends TriggerHandler {
        public EmptyHandler(System.TriggerOperation operation) {
            super(operation, new List<SObject>(), new Map<Id, SObject>());
        }
    }

    @IsTest
    static void runDispatchesEachOperationToItsMethod() {
        Map<System.TriggerOperation, String> expected = new Map<System.TriggerOperation, String>{
            System.TriggerOperation.BEFORE_INSERT => 'beforeInsert',
            System.TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
            System.TriggerOperation.BEFORE_DELETE => 'beforeDelete',
            System.TriggerOperation.AFTER_INSERT => 'afterInsert',
            System.TriggerOperation.AFTER_UPDATE => 'afterUpdate',
            System.TriggerOperation.AFTER_DELETE => 'afterDelete',
            System.TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
        };
        for (System.TriggerOperation operation : expected.keySet()) {
            RecordingHandler handler = new RecordingHandler(operation);
            handler.run();
            Assert.areEqual(new List<String>{ expected.get(operation) }, handler.calls, String.valueOf(operation));
            new EmptyHandler(operation).run();
        }
    }

    @IsTest
    static void runOutsideATriggerFails() {
        try {
            new TriggerHandler().run();
            Assert.fail('run() outside a trigger must throw.');
        } catch (ELogixException e) {
            Assert.areEqual('NOT_IN_TRIGGER', e.code);
        }
    }
}
