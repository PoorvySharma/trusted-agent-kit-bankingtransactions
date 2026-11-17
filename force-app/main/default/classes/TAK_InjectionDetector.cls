/**
 * Scores text for prompt-injection and social-engineering signals aimed at banking agents.
 *
 * Each rule adds its weight once; the score is capped at 100. The gateway blocks when the
 * score reaches the policy's Injection Threshold (default 50). Weights are tuned so that a
 * single strong signal (e.g. "ignore previous instructions", "bypass the approval") blocks,
 * while weaker signals (urgency, "transfer all", authority claims) only block in combination.
 * That keeps ordinary customer requests such as "please transfer all of my savings to
 * checking" working.
 *
 * Text is normalised first: lower-cased, zero-width characters removed (their presence is
 * itself a signal), whitespace collapsed.
 *
 * This is a deterministic first line of defence, not a complete one. See
 * docs/MODEL_RISK_TEMPLATE.md for known limitations (paraphrase, other languages, encodings).
 *
 * The rule-harness in /tools extracts the patterns marked @rule and replays them in Java,
 * so keep each pattern on one line directly below its marker.
 */
public inherited sharing class TAK_InjectionDetector {
    public static final Integer MAX_SCAN_LENGTH = 100000;
    public static final Integer HIDDEN_CHARACTER_WEIGHT = 20;

    // @rule HIDDEN hidden_characters 20
    private static final String HIDDEN_CHARS = '[\\u200B-\\u200D\\u2060\\uFEFF\\u202A-\\u202E]';

    public class Rule {
        public String name;
        public Integer weight;
        public Pattern compiled;

        public Rule(String name, Integer weight, String regex) {
            this.name = name;
            this.weight = weight;
            this.compiled = Pattern.compile(regex);
        }
    }

    public class Result {
        public Integer score = 0;
        public List<String> reasons = new List<String>();

        public Boolean exceeds(Integer threshold) {
            Integer t = threshold == null ? TAK_PolicyService.DEFAULT_INJECTION_THRESHOLD : threshold;
            return score >= t;
        }
    }

    private static List<Rule> ruleCache;

    private static List<Rule> rules() {
        if (ruleCache != null) {
            return ruleCache;
        }
        ruleCache = new List<Rule>();
        // @rule INJ override_instructions 60
        add('override_instructions', 60, '\\b(?:ignore|disregard|forget|override|bypass)\\s+(?:(?:all|any|the|your|of|my|these|those)\\s+)*(?:previous|prior|above|earlier|preceding|original|system|initial)\\s+(?:instructions?|rules?|prompts?|directions?|guidelines?|context|messages?)');
        // @rule INJ reveal_system_prompt 60
        add('reveal_system_prompt', 60, '\\b(?:reveal|show|print|repeat|output|display|dump|leak|tell)\\s+(?:me\\s+|us\\s+)?(?:your|the)\\s+(?:system\\s+prompt|hidden\\s+(?:prompt|instructions)|initial\\s+(?:prompt|instructions)|original\\s+instructions|system\\s+instructions|developer\\s+(?:prompt|instructions)|internal\\s+instructions)');
        // @rule INJ ask_instructions 30
        add('ask_instructions', 30, '\\bwhat\\s+(?:are|were)\\s+your\\s+(?:instructions|rules|system\\s+prompt|guidelines)\\b');
        // @rule INJ role_override 50
        add('role_override', 50, '\\b(?:you\\s+are\\s+now|from\\s+now\\s+on\\s+you\\s+are|act\\s+as|pretend\\s+(?:to\\s+be|you\\s+are)|roleplay\\s+as)\\s+(?:an?\\s+|the\\s+)?(?:unrestricted|unfiltered|jailbroken|evil|dan\\b|admin(?:istrator)?|system|root|developer|superuser|bank\\s+manager\\s+with\\s+override)');
        // @rule INJ jailbreak_terms 50
        add('jailbreak_terms', 50, '\\b(?:jailbreak|developer\\s+mode|dan\\s+mode|god\\s+mode|do\\s+anything\\s+now)\\b');
        // @rule INJ role_markers 40
        add('role_markers', 40, '(?:<\\|im_start\\|>|<\\|system\\|>|<\\|endoftext\\|>|\\[/?(?:system|inst)\\]|###\\s*(?:system|instruction)|\\bnew\\s+instructions?\\s*:|\\bbegin\\s+system\\s+prompt\\b)');
        // @rule INJ control_bypass 60
        add('control_bypass', 60, '\\b(?:bypass|skip|disable|circumvent|turn\\s+off|ignore|override|get\\s+around)\\s+(?:the\\s+|all\\s+|any\\s+|your\\s+|these\\s+)?(?:approvals?|approval\\s+(?:process|step|gate)|verification|kyc|aml|fraud\\s+(?:checks?|screening|controls?|detection)|transfer\\s+limits?|daily\\s+limits?|guardrails?|safety\\s+(?:checks?|rules?)|security\\s+(?:checks?|controls?)|compliance\\s+(?:checks?|review)|policy|policies|audit\\s+log(?:ging)?|logging)\\b');
        // @rule INJ secrecy 40
        add('secrecy', 40, '\\b(?:do\\s+not|don\'t|dont|never)\\s+(?:tell|inform|notify|alert|log|record|mention\\s+(?:this\\s+)?to)\\s+(?:the\\s+)?(?:user|customer|client|compliance|auditors?|anyone|security|bank|account\\s+holder)');
        // @rule INJ mass_transfer 30
        add('mass_transfer', 30, '\\b(?:transfer|send|wire|move|withdraw)\\s+(?:all|everything|the\\s+entire|every\\s+(?:dollar|cent))\\b');
        // @rule INJ exfiltration 30
        add('exfiltration', 30, '\\b(?:send|post|upload|forward|exfiltrate|email)\\b[^.]{0,80}?\\bto\\s+(?:https?://|[a-z0-9._%+-]+@)');
        // @rule INJ authority_claim 25
        add('authority_claim', 25, '\\b(?:authorized|authorised|approved|instructed|requested|ordered)\\s+by\\s+(?:the\\s+)?(?:admin(?:istrator)?|ceo|cfo|compliance|security\\s+team|it\\s+department|management|anthropic|openai|salesforce|system|developers?)\\b');
        // @rule INJ urgency_pressure 15
        add('urgency_pressure', 15, '\\b(?:urgent|urgently|immediately|right\\s+now|asap|within\\s+the\\s+next\\s+\\d+\\s+minutes)\\b');
        // @rule INJ encoded_payload 25
        add('encoded_payload', 25, '[a-z0-9+/]{120,}={0,2}');
        // @rule INJ tool_manipulation 50
        add('tool_manipulation', 50, '\\b(?:call|invoke|execute|run|trigger)\\s+(?:the\\s+)?(?:\\w+\\s+)?(?:function|tool|action|api)\\b[^.]{0,60}?\\b(?:without|with\\s+no|skipping)\\s+(?:approval|verification|logging|checks?|confirmation)');
        return ruleCache;
    }

    private static void add(String name, Integer weight, String regex) {
        ruleCache.add(new Rule(name, weight, regex));
    }

    public static String normalize(String input) {
        if (input == null) {
            return '';
        }
        String s = input.length() > MAX_SCAN_LENGTH ? input.substring(0, MAX_SCAN_LENGTH) : input;
        s = s.replaceAll(HIDDEN_CHARS, '');
        s = s.toLowerCase();
        s = s.replaceAll('\\s+', ' ');
        return s.trim();
    }

    public static Result scan(String input) {
        Result res = new Result();
        if (String.isBlank(input)) {
            return res;
        }
        String raw = input.length() > MAX_SCAN_LENGTH ? input.substring(0, MAX_SCAN_LENGTH) : input;
        if (Pattern.compile(HIDDEN_CHARS).matcher(raw).find()) {
            res.score += HIDDEN_CHARACTER_WEIGHT;
            res.reasons.add('hidden_characters');
        }
        String text = normalize(raw);
        for (Rule r : rules()) {
            if (r.compiled.matcher(text).find()) {
                res.score += r.weight;
                res.reasons.add(r.name);
            }
        }
        if (res.score > 100) {
            res.score = 100;
        }
        return res;
    }

    /** Collects every string value (and key) in a deserialized JSON structure for scanning. */
    public static String flatten(Object value) {
        List<String> out = new List<String>();
        collect(value, out, 0);
        return String.join(out, ' \n ');
    }

    private static void collect(Object value, List<String> out, Integer depth) {
        if (value == null || depth > 20) {
            return;
        }
        if (value instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) value;
            for (String k : m.keySet()) {
                out.add(k);
                collect(m.get(k), out, depth + 1);
            }
        } else if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                collect(item, out, depth + 1);
            }
        } else if (value instanceof String) {
            out.add((String) value);
        }
    }
}
