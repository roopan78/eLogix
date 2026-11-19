# eLogix ERP — Master Development Specification

## 1. Project Overview

You are acting as a Principal Salesforce Solution Architect, Senior Apex Developer, Salesforce LWC Developer, and Technical Lead.

Your responsibility is to architect and implement eLogix ERP, an enterprise-grade Logistics and Supply Chain Management platform built entirely on Salesforce.

### Product Identity

- Product Name: eLogix ERP
- Product Category: Enterprise Logistics ERP
- Platform: Salesforce
- Primary Environment: Salesforce Developer Edition
- Architecture: Modular, service-oriented Apex architecture
- Frontend: Lightning Web Components (LWC) and SLDS
- Backend: Apex
- Automation: Salesforce Flow and Platform Events
- Analytics: Salesforce Reports and Dashboards
- Development: Salesforce DX, VS Code, Claude Code
- Source Control: Git

### Product Vision

eLogix ERP centralizes logistics operations, including customer management, shipment requests, quotations, fleet allocation, warehouse operations, freight pricing, shipment tracking, delivery, invoicing, and reverse logistics.

The application must demonstrate realistic enterprise business workflows rather than merely implementing CRUD functionality.

## 2. Mandatory Development Principles

Follow these principles throughout development.

1. Build modular, reusable and maintainable code.
2. Follow Apex Enterprise Patterns concepts.
3. Do not introduce unnecessary third-party dependencies.
4. Do not install fflib unless explicitly approved.
5. Maintain one Apex trigger per object.
6. Keep triggers extremely thin.
7. Implement Trigger Handler, Service, Selector and Domain responsibilities separately.
8. Bulkify all Apex operations.
9. Never perform SOQL or DML inside loops.
10. Enforce CRUD, FLS and record-sharing requirements.
11. Use `with sharing` or appropriate explicit sharing declarations.
12. Use user-mode database operations or `Security.stripInaccessible()` where appropriate.
13. Avoid hardcoded Salesforce record IDs.
14. Use Custom Metadata Types for configurable business rules.
15. Use Custom Labels for user-facing messages.
16. Use Custom Permissions for sensitive business operations.
17. Implement centralized exception handling.
18. Implement meaningful Apex logging without exposing sensitive data.
19. Prevent duplicate transaction processing.
20. Maintain audit history for important business events.
21. Use Queueable Apex for asynchronous processing.
22. Use Batch Apex for large-volume processing.
23. Use Platform Events for suitable event-driven workflows.
24. Keep Apex controllers thin and delegate business logic to services.
25. Build reusable LWC components.
26. Use SLDS and standard Lightning components wherever possible.
27. Include loading, empty, success and error states in LWCs.
28. Write meaningful Apex test classes.
29. Never bypass tests to force deployment.
30. Do not claim a feature is complete until it has been deployed and verified.

## 3. Target Architecture

Implement the following layered architecture.

### Experience Layer
- Lightning Application
- Lightning Web Components
- Standard Salesforce Record Pages
- Salesforce Reports
- Salesforce Dashboards

### Application Layer
- Shipment Application Service
- Fleet Application Service
- Warehouse Application Service
- Finance Application Service
- Return Application Service

### Domain Layer
- Shipment Domain
- Fleet Domain
- Inventory Domain
- Pricing Domain
- Billing Domain

### Business Logic Layer
- Apex Services
- Selectors
- Validators
- DTOs
- Trigger Handlers
- Domain Policies

### Automation Layer
- Record-Triggered Flows
- Scheduled Flows
- Queueable Apex
- Batch Apex
- Platform Events

### Integration Layer
- REST Integration Clients
- Named Credentials
- External System Adapters
- Integration Logging
- Retry and Idempotency Handling

### Data Layer
- Standard Objects
- Custom Objects
- Custom Metadata Types
- Custom Settings where justified
- Salesforce Files

## 4. Business Modules and Data Model

Use standard Salesforce objects whenever appropriate.

### A. Customer Management

Standard Objects:
- Account
- Contact

Support:
- Customer classification
- Active/inactive customer status
- Billing and shipping addresses
- Customer contacts
- Customer credit terms

### B. Business Unit Management

Custom Object: Business_Unit__c

Fields:
- Name
- Business_Unit_Code__c
- Region__c
- CurrencyIsoCode where applicable
- Is_Active__c

Design for multiple business units within one Salesforce org.

### C. Shipment Request and Quotation

Custom Objects:
- Shipment_Request__c
- Quotation__c
- Quotation_Line__c

Shipment Request fields:
- Request_Number__c
- Customer__c
- Business_Unit__c
- Origin__c
- Destination__c
- Requested_Pickup_Date__c
- Expected_Delivery_Date__c
- Total_Weight__c
- Status__c

Quotation fields:
- Quotation_Number__c
- Shipment_Request__c
- Base_Freight__c
- Weight_Charge__c
- Distance_Charge__c
- Fuel_Surcharge__c
- Insurance_Charge__c
- Discount__c
- Tax_Amount__c
- Total_Amount__c
- Valid_Until__c
- Status__c

### D. Shipment Management

Custom Objects:
- Shipment__c
- Shipment_Item__c

Shipment fields:
- Shipment_Number__c (Auto Number)
- Shipment_Request__c
- Quotation__c
- Customer__c
- Business_Unit__c
- Origin__c
- Destination__c
- Weight__c
- Distance__c
- Freight_Amount__c
- Pickup_Date__c
- Expected_Delivery_Date__c
- Actual_Delivery_Date__c
- Status__c
- Priority__c
- Vehicle__c
- Driver__c
- Latest_Location__c

Shipment Item fields:
- Shipment__c
- Item_Name__c
- SKU__c
- Quantity__c
- Weight__c
- Declared_Value__c
- Package_Type__c

### E. Fleet Management

Custom Objects:
- Vehicle__c
- Driver__c
- Vehicle_Assignment__c
- Vehicle_Maintenance__c

Vehicle fields:
- Vehicle_Number__c
- Vehicle_Type__c
- Capacity__c
- Registration_Expiry__c
- Insurance_Expiry__c
- Status__c
- Business_Unit__c

Driver fields:
- Name
- License_Number__c
- License_Expiry__c
- Phone__c
- Status__c
- Business_Unit__c

Vehicle Assignment fields:
- Vehicle__c
- Driver__c
- Shipment__c
- Assignment_Start__c
- Assignment_End__c
- Status__c

Maintenance fields:
- Vehicle__c
- Maintenance_Type__c
- Scheduled_Date__c
- Completion_Date__c
- Cost__c
- Status__c

### F. Warehouse and Inventory Management

Custom Objects:
- Warehouse__c
- Inventory__c
- Stock_Movement__c

Warehouse fields:
- Warehouse_Code__c
- Location__c
- Capacity__c
- Status__c
- Business_Unit__c

Inventory fields:
- Warehouse__c
- SKU__c
- Product_Name__c
- Available_Quantity__c
- Reserved_Quantity__c
- Reorder_Level__c

Stock Movement fields:
- Warehouse__c
- Inventory__c
- Movement_Type__c
- Quantity__c
- Reference_Shipment__c
- Movement_Date__c
- Remarks__c

Maintain stock through controlled stock movements rather than arbitrary quantity updates.

### G. Route and Pricing Management

Custom Objects:
- Route__c
- Route_Stop__c
- Rate_Card__c
- Freight_Charge__c

Route fields:
- Route_Code__c
- Origin__c
- Destination__c
- Distance__c
- Estimated_Transit_Hours__c
- Status__c

Rate Card fields:
- Rate_Card_Name__c
- Vehicle_Type__c
- Base_Freight__c
- Rate_Per_KG__c
- Rate_Per_KM__c
- Fuel_Surcharge_Percent__c
- Insurance_Percent__c
- Minimum_Freight__c
- Effective_From__c
- Effective_To__c
- Is_Active__c

Freight Charge fields:
- Shipment__c
- Charge_Type__c
- Description__c
- Amount__c

Pricing must be configurable, date-aware and based on the applicable rate card.

### H. Tracking and Delivery

Custom Objects:
- Tracking_Event__c
- Delivery__c
- Proof_of_Delivery__c

Tracking fields:
- Shipment__c
- Event_Type__c
- Location__c
- Event_Timestamp__c
- Remarks__c
- Source__c

Delivery fields:
- Shipment__c
- Receiver_Name__c
- Delivery_Date__c
- Delivery_Status__c
- Failure_Reason__c

POD fields:
- Shipment__c
- Delivery__c
- Receiver_Name__c
- Signature_Reference__c
- Delivery_Notes__c

Use Salesforce Files for uploaded delivery evidence.

### I. Finance and Billing

Custom Objects:
- Invoice__c
- Invoice_Line__c
- Payment__c

Invoice fields:
- Invoice_Number__c
- Shipment__c
- Customer__c
- Invoice_Date__c
- Due_Date__c
- Subtotal__c
- Tax__c
- Total_Amount__c
- Paid_Amount__c
- Balance_Amount__c
- Status__c

Payment fields:
- Invoice__c
- Payment_Reference__c
- Payment_Date__c
- Amount__c
- Payment_Method__c
- Status__c

Maintain financial consistency and prevent duplicate invoices.

### J. Reverse Logistics

Custom Objects:
- Return_Request__c
- Claim__c

Return Request fields:
- Return_Number__c
- Original_Shipment__c
- Customer__c
- Return_Reason__c
- Return_Type__c
- Pickup_Address__c
- Status__c

Claim fields:
- Return_Request__c
- Shipment__c
- Claim_Type__c
- Claim_Amount__c
- Resolution__c
- Status__c

## 5. Business Rules

Implement the following business policies.

### Customer Rules
- Inactive customers cannot create new shipment requests.
- Mandatory customer information must be present.
- Customer-specific credit terms must be respected.

### Shipment Rules
- Weight must be greater than zero.
- Distance must be greater than zero.
- Pickup date must be valid.
- Expected delivery date must be after pickup.
- Shipment must have at least one item before confirmation.
- Shipment status must follow an allowed transition.
- Delivered shipments cannot be dispatched again.
- Cancelled shipments cannot be processed further.

### Freight Rules

Calculate freight using:

Base Freight
+ Weight × Weight Rate
+ Distance × Distance Rate
+ Fuel Surcharge
+ Insurance
+ Additional Charges
- Discount
+ Applicable Tax

Use a dedicated FreightCalculationService.

Do not hardcode pricing values in Apex.

### Fleet Rules
- Vehicle must be active.
- Vehicle must have sufficient carrying capacity.
- Driver must be active.
- Driver must have a valid license.
- Vehicle insurance and registration must be valid.
- Vehicle and driver cannot have conflicting active assignments.
- Maintenance vehicles cannot be assigned.

Implement appropriate record locking and overlap checks to reduce concurrent allocation conflicts.

### Warehouse Rules
- Stock cannot become negative.
- Reserved stock cannot exceed available stock.
- All stock changes must have an audit trail.
- Dispatch must validate required inventory.
- Returns must undergo inspection before restocking.

### Invoice Rules
- Invoice must not be generated twice for the same shipment and billing milestone.
- Invoice total must match its line items.
- Payments cannot exceed the outstanding balance unless explicitly configured for advance payments.
- Paid invoices cannot be arbitrarily modified.

### Return Rules
- Return must reference an original shipment.
- Return reason is mandatory.
- Return approval is required before pickup scheduling.
- Return inspection must be completed before resolution.

## 6. Shipment Lifecycle

Implement a controlled status transition model.

Draft → Requested → Quoted → Confirmed → Ready for Dispatch → Dispatched → In Transit → Out for Delivery → Delivered → Closed.

Exception statuses:
- On Hold
- Delayed
- Failed Delivery
- Damaged
- Lost
- Cancelled
- Return Initiated

Create a ShipmentStatusPolicy or equivalent configurable policy service.

Every meaningful status change must generate a Tracking_Event__c record.

Prevent unauthorized or invalid status changes.

## 7. Apex Package Structure

Use the following logical structure.

classes/
- base/
- common/
- crm/
- shipment/
- fleet/
- warehouse/
- pricing/
- tracking/
- finance/
- returns/
- integrations/
- selectors/
- handlers/
- batch/
- queueable/
- events/
- test/

Core classes:

ShipmentTriggerHandler
ShipmentService
ShipmentSelector
ShipmentStatusPolicy
FreightCalculationService
FleetAllocationService
VehicleAvailabilityService
WarehouseService
InventoryService
TrackingService
DeliveryService
InvoiceService
PaymentService
ReturnService
IntegrationLogService
GPSIntegrationService
PaymentIntegrationService

Create a single trigger per relevant object.

Keep all domain rules in service and policy classes, not inside triggers or LWC controllers.

Use a consistent result/exception pattern for service operations.

Use DTOs only when they improve separation between UI, domain and integration layers.

## 8. LWC Application

Create an application named eLogix ERP.

Recommended navigation:

- Executive Dashboard
- Shipment Requests
- Quotations
- Shipments
- Fleet
- Drivers
- Warehouses
- Inventory
- Routes
- Rate Cards
- Tracking
- Deliveries
- Invoices
- Payments
- Returns
- Claims

Develop these reusable LWCs:

- elogixDashboard
- shipmentManagement
- shipmentBooking
- shipmentDetails
- shipmentTimeline
- quotationBuilder
- fleetManagement
- vehicleAllocation
- warehouseManagement
- inventoryManagement
- trackingConsole
- deliveryManagement
- invoiceManagement
- returnManagement
- reusableDataTable
- statusBadge
- confirmationDialog
- loadingIndicator

Use:
- Lightning Data Service where appropriate.
- lightning-record-edit-form for standard record editing.
- Apex for complex operations.
- SLDS for styling.
- Responsive layouts.
- Accessible controls.
- Toast notifications.
- Consistent error handling.

Do not build a custom dashboard in place of Salesforce Reports and Dashboards. Build the management screens as LWCs and use native dashboards for executive analytics.

## 9. Salesforce Reports and Dashboards

Create a dashboard named:

eLogix - Executive Operations Dashboard

Recommended components:

- Total Shipments
- Active Shipments
- Delivered Shipments
- Delayed Shipments
- Total Freight Revenue
- Outstanding Invoices
- Fleet Availability
- Shipment Status Distribution
- Monthly Shipment Trends
- Revenue Trends
- Warehouse Stock Summary

Create operational reports for:
- Shipment Register
- Delayed Shipments
- Vehicle Utilization
- Driver Assignments
- Delivery Performance
- Revenue by Month
- Outstanding Invoices
- Returns and Claims

Use report types and folders where required.

Verify all dashboard metadata against the target org's supported features and API version.

## 10. Salesforce Automation

Use Record-Triggered Flows for appropriate declarative automation.

Create:
- Shipment Request Validation Flow
- Quotation Approval Flow
- Delivery Completion Flow
- Invoice Generation Flow
- Payment Status Update Flow
- Return Approval Flow
- SLA Monitoring Flow where appropriate

Use Apex for complex transactional validation, allocation and financial logic.

Use Platform Events for appropriate asynchronous event-driven processing.

Do not duplicate the same business rule in multiple automation mechanisms.

Document which component owns each business rule.

## 11. Integration Architecture

Create integration interfaces and mock implementations for:

- GPS provider
- Payment gateway
- External accounting ERP
- Mapping and distance provider
- Notification provider

Use Named Credentials for real callouts.

Use Queueable Apex with callout support when appropriate.

Implement:
- Request and response DTOs
- Timeout handling
- Retry policies
- Idempotency keys
- Integration logging
- Error categorization
- Dead-letter or failed-message handling where feasible

Do not invent live integration connectivity.

The MVP must work without any paid external service.

## 12. Security Architecture

Implement:
- Permission Sets
- Custom Permissions
- Role-based access
- Record ownership and sharing
- CRUD/FLS enforcement
- Apex sharing enforcement
- Protected financial fields
- Appropriate external-user access boundaries if Experience Cloud is introduced later

Recommended roles:
- System Administrator
- Logistics Manager
- Sales Executive
- Operations Executive
- Fleet Manager
- Warehouse Manager
- Finance Executive
- Customer Service Executive

Design permissions so users can only perform authorized business operations.

## 13. Testing Strategy

Write Apex test classes for all important business services.

Test scenarios:
- Successful shipment creation.
- Invalid shipment request.
- Freight calculation.
- Rate card selection.
- Vehicle capacity validation.
- Driver license validation.
- Conflicting fleet assignment.
- Invalid shipment status transition.
- Tracking event creation.
- Successful delivery.
- Duplicate invoice prevention.
- Payment reconciliation.
- Stock movement validation.
- Return approval and inspection.
- Bulk record processing.
- Exception and rollback scenarios.

Use test data factories and assertions.

Do not rely on SeeAllData=true.

Test bulk scenarios and realistic boundary conditions.

Create LWC Jest tests for critical reusable components and user interactions if the local Jest environment is available.

Target at least 85% meaningful Apex coverage for the implemented functionality, without writing meaningless tests just to inflate coverage.

## 14. Sample Data

Create a repeatable demo-data script.

Include:
- 10 customers.
- 5 business units or suitable regional examples, subject to the demo data model.
- 10 vehicles.
- 10 drivers.
- 5 warehouses.
- 10 routes.
- 20 shipment requests.
- 15 quotations.
- 20 shipments across different statuses.
- Tracking events.
- Invoices.
- Payments.
- Return requests.

Use realistic Indian logistics scenarios:
- Chennai to Bangalore
- Madurai to Coimbatore
- Chennai to Hyderabad
- Bangalore to Mumbai
- Madurai to Chennai

Do not hardcode record IDs. Query created records by unique business keys.

Make seed scripts idempotent so repeated execution does not create duplicates.

## 15. Documentation

Maintain these project documents:

docs/BUSINESS_REQUIREMENTS.md
docs/SOLUTION_ARCHITECTURE.md
docs/DATA_MODEL.md
docs/BUSINESS_RULES.md
docs/SHIPMENT_LIFECYCLE.md
docs/AUTOMATION_DESIGN.md
docs/SECURITY_DESIGN.md
docs/INTEGRATION_DESIGN.md
docs/API_SPECIFICATION.md
docs/TEST_STRATEGY.md
docs/DEPLOYMENT_GUIDE.md
docs/DEMO_SCRIPT.md

Update documentation as implementation decisions change.

## 16. Development Workflow

Use this exact process:

1. Inspect the current Salesforce project.
2. Inspect connected Salesforce org and API version.
3. Verify target org capabilities and limits.
4. Create implementation checklist.
5. Prepare data model.
6. Implement metadata.
7. Deploy metadata.
8. Implement Apex.
9. Run Apex tests.
10. Implement Flows.
11. Implement LWCs.
12. Deploy and verify.
13. Create Reports and Dashboards.
14. Seed sample data.
15. Run end-to-end tests.
16. Perform security and deployment validation.
17. Prepare interview demonstration.

After every phase:
- Summarize files created and changed.
- List deployment results.
- List test results.
- List known issues.
- Update project documentation.
- Recommend the next phase.

Never proceed silently when deployment or testing fails.

## 17. Two-Day Delivery Priority

### Day 1
- Project inspection and setup.
- Architecture and documentation.
- Data model and metadata.
- Shipment and quotation services.
- Freight calculation.
- Fleet allocation.
- Status transition policy.
- Tracking history.
- Initial Apex tests.

### Day 2
- Warehouse and inventory essentials.
- Delivery and invoice automation.
- Returns functionality if time permits.
- LWC screens.
- Native Salesforce Reports and Dashboards.
- Demo data.
- Regression tests.
- Deployment validation.
- Interview demonstration.

Prioritize functional P0 modules before P1 and P2.

## 18. Critical Delivery Constraints

- Target a standard Salesforce Developer Edition org.
- Never assume Enterprise or Unlimited Edition features.
- Check edition-specific feature availability.
- Respect Salesforce storage, API and governor limits.
- Avoid unnecessary asynchronous processing.
- Avoid unnecessary object and component proliferation.
- Do not introduce external paid services.
- Keep the implementation deployable.
- Do not use fake success responses.
- Do not fabricate completed tests.
- Preserve existing code unless a change is necessary.
- Avoid broad refactoring without approval.
- Use the existing API version unless a verified requirement necessitates an upgrade.

## 19. First Task — Do Not Skip

Before writing application code:

1. Inspect the existing project and package configuration.
2. Verify the Salesforce CLI connection.
3. Inspect the target org edition, API version and relevant limits.
4. Create CLAUDE.md with these engineering rules.
5. Create the documentation structure.
6. Produce the complete object relationship design.
7. Produce the implementation dependency graph.
8. Create a two-day execution checklist.
9. Identify any unsupported or risky features.
10. Present the architecture and checklist for review.

Do not generate the entire application immediately.

Implement one independently deployable phase at a time.

Start with Phase 1: project setup, architecture documentation and Salesforce metadata foundation.

Your objective is to deliver a working, polished and technically credible eLogix ERP prototype within 48 hours.