# eLogix ERP Security Matrix

This matrix describes the local Phase 9 model. The roles and sharing rules have not been deployed or validated in a Salesforce org. Object and field permissions are generated from [`elogix-security.mjs`](../scripts/node/model/elogix-security.mjs); record sharing metadata is generated from the same model.

## Roles

| Role                       | Reports to        | Salesforce access source                                                                   |
| -------------------------- | ----------------- | ------------------------------------------------------------------------------------------ |
| Logistics Manager          | Top               | `eLogix_Logistics_Manager`; hierarchy access to subordinate-owned records                  |
| Sales Executive            | Logistics Manager | `eLogix_Sales_Executive`                                                                   |
| Operations Executive       | Logistics Manager | `eLogix_Operations_Executive`                                                              |
| Fleet Manager              | Logistics Manager | `eLogix_Fleet_Manager`                                                                     |
| Warehouse Manager          | Logistics Manager | `eLogix_Warehouse_Manager`                                                                 |
| Finance Executive          | Logistics Manager | `eLogix_Finance_Executive`                                                                 |
| Customer Service Executive | Logistics Manager | `eLogix_Customer_Service_Executive`                                                        |
| Administrator              | No eLogix role    | `eLogix_Administrator` permission set; existing System Administrator profile as configured |

## Private object access

`C` create, `R` read, `E` edit, `D` delete, `V` view all, `M` modify all. A dash means no object permission. Sharing cannot grant an operation the permission set does not grant.

| Object           |  Admin | Logistics Manager | Sales | Operations | Fleet | Warehouse | Finance | Customer Service | Record sharing in Phase 9                                            |
| ---------------- | -----: | ----------------: | ----: | ---------: | ----: | --------: | ------: | ---------------: | -------------------------------------------------------------------- |
| Shipment Request | CREDVM |              CREV |   CRE |         RE |     - |         - |       R |              CRE | Operations R; Customer Service R                                     |
| Quotation        | CREDVM |              CREV |   CRE |          R |     - |         - |       R |                R | Operations R; Customer Service R                                     |
| Shipment         | CREDVM |              CREV |     R |        CRE |    RV |         R |       R |                R | Operations Edit; Fleet, Warehouse, Finance and Customer Service Read |
| Invoice          | CREDVM |                RV |     R |          R |     - |         - |    CREV |                R | Future work                                                          |
| Return Request   | CREDVM |              CREV |     R |         RE |     - |        RE |       R |              CRE | Future work                                                          |
| Claim            | CREDVM |              CREV |     - |          R |     - |         - |      RE |              CRE | Future work                                                          |

Other object grants, protected field rules, controller access and custom permissions are documented in [SECURITY_DESIGN.md](SECURITY_DESIGN.md). Public Read Only reference data and parent-controlled detail objects follow the OWD and permission-set model in that document.

## Explicit limitations

- **Business Unit isolation is not implemented.** `Business_Unit__c` is not an access-control boundary. No BU filter, sharing rule or Apex enforcement exists. Cross-BU record visibility follows normal OWD, role hierarchy, sharing and object permissions.
- Invoice, Return Request and Claim sharing rules are future work.
- Role hierarchy grants access to subordinate-owned records, but does not itself grant object or field permission.
- The Logistics Manager role has no profile-level all-access bypass. The Administrator has no eLogix role and retains eLogix access through `eLogix_Administrator`.
- Dashboard execution uses the fixed administrator configured by analytics generation. The dashboard folder is shared only to Logistics Manager; reports are shared with all internal users and run as the viewer.
- The generated metadata still needs a manual target-org validation and login-as review.
