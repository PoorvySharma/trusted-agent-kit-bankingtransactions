/**
 * Loads Agent Policy custom metadata. Lookups are case-insensitive by action name.
 * An action with no policy is treated as not allowed (fail-closed) by the gateway.
 */
public inherited sharing class TAK_PolicyService {
    public static final Integer DEFAULT_INJECTION_THRESHOLD = 50;
    public static final Integer DEFAULT_APPROVAL_EXPIRY_MINUTES = 60;

    public class Policy {
        public String sourceName;
        public String actionName;
        public String handlerClass;
        public String riskTier;
        public Boolean active = true;
        public Boolean requiresApproval = false;
        public Decimal approvalAmountThreshold;
        public String amountField;
        public Integer injectionThreshold = DEFAULT_INJECTION_THRESHOLD;
        public Integer maxCallsPerHour;
        public Boolean redactOutput = true;
        public Integer approvalExpiryMinutes = DEFAULT_APPROVAL_EXPIRY_MINUTES;
        public String approverQueue;
    }

    private static Map<String, Policy> cache;

    @TestVisible
    private static Map<String, Policy> testOverrides;

    public static Policy forAction(String actionName) {
        if (String.isBlank(actionName)) {
            return null;
        }
        return all().get(actionName.trim().toLowerCase());
    }

    public static Map<String, Policy> all() {
        if (testOverrides != null) {
            return testOverrides;
        }
        if (cache == null) {
            cache = new Map<String, Policy>();
            for (TAK_Agent_Policy__mdt rec : TAK_Agent_Policy__mdt.getAll().values()) {
                Policy p = fromRecord(rec);
                if (String.isNotBlank(p.actionName)) {
                    cache.put(p.actionName.trim().toLowerCase(), p);
                }
            }
        }
        return cache;
    }

    @TestVisible
    private static Policy fromRecord(TAK_Agent_Policy__mdt rec) {
        Policy p = new Policy();
        p.sourceName = rec.DeveloperName;
        p.actionName = String.isNotBlank(rec.Action_Name__c) ? rec.Action_Name__c : rec.DeveloperName;
        p.handlerClass = rec.Handler_Class__c;
        p.riskTier = rec.Risk_Tier__c;
        p.active = rec.Active__c == true;
        p.requiresApproval = rec.Requires_Approval__c == true;
        p.approvalAmountThreshold = rec.Approval_Amount_Threshold__c;
        p.amountField = rec.Amount_Field__c;
        if (rec.Injection_Threshold__c != null) {
            p.injectionThreshold = rec.Injection_Threshold__c.intValue();
        }
        if (rec.Max_Calls_Per_Hour__c != null) {
            p.maxCallsPerHour = rec.Max_Calls_Per_Hour__c.intValue();
        }
        p.redactOutput = rec.Redact_Output__c == true;
        if (rec.Approval_Expiry_Minutes__c != null && rec.Approval_Expiry_Minutes__c > 0) {
            p.approvalExpiryMinutes = rec.Approval_Expiry_Minutes__c.intValue();
        }
        p.approverQueue = rec.Approver_Queue__c;
        return p;
    }

    /** Test hook: replaces metadata with in-memory policies for the rest of the transaction. */
    @TestVisible
    private static void registerForTest(Policy p) {
        if (testOverrides == null) {
            testOverrides = new Map<String, Policy>();
        }
        testOverrides.put(p.actionName.trim().toLowerCase(), p);
    }
}
