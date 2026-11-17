/**
 * Masks US banking PII before text is stored in logs, shown to approvers, or (when the
 * policy asks) returned to the language model.
 *
 * Detectors run in a fixed order so earlier tokens cannot be re-matched by later ones:
 *   SSN (formatted) -> SSN (labelled) -> payment card (Luhn-checked) -> routing number
 *   (ABA-checksum, labelled) -> account number (labelled) -> email -> phone
 *
 * Cards and accounts keep their last four digits so approvers can still recognise them.
 * Over-redaction is preferred to under-redaction: an unlabelled 10-digit number is masked
 * as a phone number.
 *
 * The rule-harness in /tools extracts the patterns marked @rule and replays them in Java,
 * so keep each pattern on one line directly below its marker.
 */
public inherited sharing class TAK_PIIRedactor {
    public static final Integer MAX_INPUT_LENGTH = 100000;

    // @rule PII SSN 0
    private static final String SSN_PATTERN = '\\b(?!000|666|9\\d\\d)\\d{3}[- ](?!00)\\d{2}[- ](?!0000)\\d{4}\\b';
    // @rule PII SSN_LABELLED 1
    private static final String SSN_LABELLED_PATTERN = '(?i)\\b(?:ssn|social security(?: number| no\\.?)?)\\D{0,12}(\\d{9})\\b';
    // @rule PII CARD 0
    private static final String CARD_PATTERN = '(?<![\\d-])\\d(?:[ -]?\\d){12,18}(?![\\d-])';
    // @rule PII ROUTING 1
    private static final String ROUTING_PATTERN = '(?i)(?:routing|\\baba|\\brtn)(?:\\s*(?:number|num|no\\.?|#))?\\D{0,12}(\\d{9})\\b';
    // @rule PII ACCOUNT 1
    private static final String ACCOUNT_PATTERN = '(?i)(?:account|acct)(?:\\s*(?:number|num|no\\.?|#))?\\D{0,12}(\\d{6,17})\\b';
    // @rule PII EMAIL 0
    private static final String EMAIL_PATTERN = '\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b';
    // @rule PII PHONE 0
    private static final String PHONE_PATTERN = '(?<![\\d-])(?:\\+?1[ .-]?)?(?:\\(\\d{3}\\)|\\d{3})[ .-]?\\d{3}[ .-]?\\d{4}(?![\\d-])';

    public class Result {
        public String text;
        public Map<String, Integer> counts = new Map<String, Integer>();

        public Integer total() {
            Integer n = 0;
            for (Integer c : counts.values()) {
                n += c;
            }
            return n;
        }
    }

    public static Result redact(String input) {
        Result res = new Result();
        if (String.isBlank(input)) {
            res.text = input;
            return res;
        }
        String text = input.length() > MAX_INPUT_LENGTH ? input.substring(0, MAX_INPUT_LENGTH) : input;
        text = replaceMatches(text, SSN_PATTERN, 0, 'SSN', res);
        text = replaceMatches(text, SSN_LABELLED_PATTERN, 1, 'SSN', res);
        text = replaceMatches(text, CARD_PATTERN, 0, 'CARD', res);
        text = replaceMatches(text, ROUTING_PATTERN, 1, 'ROUTING', res);
        text = replaceMatches(text, ACCOUNT_PATTERN, 1, 'ACCOUNT', res);
        text = replaceMatches(text, EMAIL_PATTERN, 0, 'EMAIL', res);
        text = replaceMatches(text, PHONE_PATTERN, 0, 'PHONE', res);
        res.text = text;
        return res;
    }

    /** Convenience wrapper returning only the redacted text. */
    public static String mask(String input) {
        return redact(input).text;
    }

    private static String replaceMatches(String input, String regex, Integer groupIdx, String kind, Result res) {
        Matcher m = Pattern.compile(regex).matcher(input);
        List<String> parts = new List<String>();
        Integer last = 0;
        while (m.find()) {
            Integer startIdx = groupIdx == 0 ? m.start() : m.start(groupIdx);
            Integer endIdx = groupIdx == 0 ? m.end() : m.end(groupIdx);
            String value = groupIdx == 0 ? m.group() : m.group(groupIdx);
            String token = tokenFor(kind, value);
            if (token == null) {
                continue;
            }
            parts.add(input.substring(last, startIdx));
            parts.add(token);
            last = endIdx;
            Integer prior = res.counts.containsKey(kind) ? res.counts.get(kind) : 0;
            res.counts.put(kind, prior + 1);
        }
        if (parts.isEmpty()) {
            return input;
        }
        parts.add(input.substring(last));
        return String.join(parts, '');
    }

    private static String tokenFor(String kind, String value) {
        String digits = value.replaceAll('[^0-9]', '');
        switch on kind {
            when 'SSN' {
                return '[SSN REDACTED]';
            }
            when 'CARD' {
                if (digits.length() < 13 || digits.length() > 19 || !passesLuhn(digits)) {
                    return null;
                }
                return '[CARD ****' + digits.right(4) + ']';
            }
            when 'ROUTING' {
                return passesAbaChecksum(digits) ? '[ROUTING REDACTED]' : null;
            }
            when 'ACCOUNT' {
                return '[ACCOUNT ****' + digits.right(4) + ']';
            }
            when 'EMAIL' {
                return '[EMAIL REDACTED]';
            }
            when 'PHONE' {
                return '[PHONE REDACTED]';
            }
        }
        return null;
    }

    @TestVisible
    private static Boolean passesLuhn(String digits) {
        Integer sum = 0;
        Boolean doubleIt = false;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            Integer d = Integer.valueOf(digits.substring(i, i + 1));
            if (doubleIt) {
                d *= 2;
                if (d > 9) {
                    d -= 9;
                }
            }
            sum += d;
            doubleIt = !doubleIt;
        }
        return sum > 0 && Math.mod(sum, 10) == 0;
    }

    @TestVisible
    private static Boolean passesAbaChecksum(String digits) {
        if (digits == null || digits.length() != 9) {
            return false;
        }
        List<Integer> w = new List<Integer>{ 3, 7, 1, 3, 7, 1, 3, 7, 1 };
        Integer sum = 0;
        for (Integer i = 0; i < 9; i++) {
            sum += Integer.valueOf(digits.substring(i, i + 1)) * w[i];
        }
        return sum > 0 && Math.mod(sum, 10) == 0;
    }
}
