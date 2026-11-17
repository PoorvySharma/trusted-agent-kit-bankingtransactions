/**
 * Hashing and canonical JSON helpers.
 *
 * Canonical JSON sorts object keys and normalises numbers (25000, 25000.0 and 25000.00
 * all become 25000) so the same request always produces the same hash. This is what
 * binds a human approval to one exact payload.
 */
public inherited sharing class TAK_Hashing {
    public static String sha256(String value) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value));
        return EncodingUtil.convertToHex(digest);
    }

    public static String canonicalJson(Object value) {
        if (value == null) {
            return 'null';
        }
        if (value instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) value;
            List<String> keys = new List<String>(m.keySet());
            keys.sort();
            List<String> parts = new List<String>();
            for (String k : keys) {
                parts.add(JSON.serialize(k) + ':' + canonicalJson(m.get(k)));
            }
            return '{' + String.join(parts, ',') + '}';
        }
        if (value instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object item : (List<Object>) value) {
                parts.add(canonicalJson(item));
            }
            return '[' + String.join(parts, ',') + ']';
        }
        if (value instanceof Integer || value instanceof Long) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).stripTrailingZeros().toPlainString();
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value).stripTrailingZeros().toPlainString();
        }
        return JSON.serialize(value);
    }

    /** Hash that identifies one exact request: action + canonical payload. */
    public static String payloadHash(String actionName, Map<String, Object> payload) {
        String action = actionName == null ? '' : actionName.trim().toLowerCase();
        return sha256(action + '\n' + canonicalJson(payload));
    }
}
