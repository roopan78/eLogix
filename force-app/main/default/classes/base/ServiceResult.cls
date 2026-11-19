/**
 * Outcome of a service operation that processes several records with partial success.
 *
 * Expected business failures are reported here per record (index into the request list), not
 * thrown. Exceptions are reserved for conditions the caller cannot handle per record, such as
 * missing configuration or no object access. See docs/APEX_ARCHITECTURE.md section 4.2.
 */
public inherited sharing class ServiceResult {
    @AuraEnabled
    public Boolean isSuccess {
        get {
            return errors.isEmpty();
        }
    }

    @AuraEnabled
    public List<ServiceError> errors { get; private set; }

    @AuraEnabled
    public List<Id> recordIds { get; private set; }

    public ServiceResult() {
        errors = new List<ServiceError>();
        recordIds = new List<Id>();
    }

    public static ServiceResult ok(List<Id> recordIds) {
        ServiceResult result = new ServiceResult();
        if (recordIds != null) {
            result.recordIds.addAll(recordIds);
        }
        return result;
    }

    public ServiceResult addRecordId(Id recordId) {
        if (recordId != null) {
            recordIds.add(recordId);
        }
        return this;
    }

    public ServiceResult addError(String code, String message, Integer recordIndex, Id recordId) {
        errors.add(new ServiceError(code, message, recordIndex, recordId));
        return this;
    }

    /** Errors reported for one request index, in the order they were added. */
    public List<ServiceError> errorsFor(Integer recordIndex) {
        List<ServiceError> matches = new List<ServiceError>();
        for (ServiceError error : errors) {
            if (error.recordIndex == recordIndex) {
                matches.add(error);
            }
        }
        return matches;
    }

    public class ServiceError {
        @AuraEnabled
        public String code;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Integer recordIndex;
        @AuraEnabled
        public Id recordId;

        public ServiceError(String code, String message, Integer recordIndex, Id recordId) {
            this.code = code;
            this.message = message;
            this.recordIndex = recordIndex;
            this.recordId = recordId;
        }
    }
}
