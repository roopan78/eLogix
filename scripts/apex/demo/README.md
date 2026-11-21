# Phase 9 demo fixtures

- `DEMO-GPS-pings.json` is a synthetic one-ping payload for the seeded `DEMO-VEH-01`, with the GPS endpoint shape. Submit only when that vehicle has an Active `Vehicle_Assignment__c` and the caller has `eLogix_Ingest_GPS`; the current Phase 9 seed leaves all DEMO vehicles unassigned.
- `../../../output/pdf/DEMO-POD-01.pdf` is a synthetic POD sample for `SHP-00146` / `DEMO-REQ-02`. It is not a real delivery record or signature and has not been uploaded or linked to Salesforce.
- `MockGpsProvider` is available in Apex and returns positions only for active trips. The current seed does not create assignments because assignments are retained as operational history and are not removable by the DEMO cleanup script.
