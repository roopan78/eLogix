/**
 * Inbound GPS endpoint (Phase 6, G1): POST /services/apexrest/elogix/gps/v1/pings
 *
 *   request   {"pings": [{"messageId": "...", "vehicleNumber": "TN01AB1234", "latitude": 13.08,
 *              "longitude": 80.27, "recordedAt": "2026-11-20T10:15:00Z", "location": "optional"}]}
 *   202       {"batchId": "...", "accepted": n}   processed asynchronously by GpsIngestionJob
 *   400       malformed body, or not 1..200 pings
 *   403       the caller lacks the eLogix_Ingest_GPS custom permission
 *
 * Thin by design: per-ping validation, vehicle mapping and throttling happen in GpsIngestionService,
 * and their results are counted in the batch's integration log.
 */
@RestResource(urlMapping='/elogix/gps/v1/pings')
global with sharing class GpsPingResource {
    private class Payload {
        List<GpsPing> pings;
    }

    @HttpPost
    global static void submit() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        if (!PermissionService.hasPermission(GpsIngestionJob.INGEST_PERMISSION)) {
            reply(response, 403, new Map<String, Object>{ 'error' => 'ACCESS_DENIED', 'message' => Label.eLogix_GPS_Access_Denied });
            return;
        }
        Payload payload;
        try {
            Blob body = RestContext.request.requestBody;
            payload = body == null ? null : (Payload) JSON.deserialize(body.toString(), Payload.class);
        } catch (JSONException e) {
            payload = null;
        }
        if (payload == null || payload.pings == null || payload.pings.isEmpty() || payload.pings.size() > GpsIngestionJob.MAX_PINGS) {
            String message = String.format(Label.eLogix_GPS_Invalid_Payload, new List<Object>{ GpsIngestionJob.MAX_PINGS });
            reply(response, 400, new Map<String, Object>{ 'error' => 'INVALID_PAYLOAD', 'message' => message });
            return;
        }
        String batchId = GpsIngestionJob.submit(payload.pings);
        reply(response, 202, new Map<String, Object>{ 'batchId' => batchId, 'accepted' => payload.pings.size() });
    }

    private static void reply(RestResponse response, Integer statusCode, Map<String, Object> body) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
