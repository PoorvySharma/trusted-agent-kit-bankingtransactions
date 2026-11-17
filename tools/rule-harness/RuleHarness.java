import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Replays Trusted Agent Kit's detection rules outside Salesforce.
 *
 * Apex uses Java's regex engine, so the patterns extracted from the Apex source by run.py
 * behave the same here. The scoring and redaction logic below mirrors
 * TAK_InjectionDetector and TAK_PIIRedactor; keep them in sync.
 *
 * Input files (written by run.py, one record per line, fields base64-encoded, tab-separated):
 *   rules.tsv   kind  name  weightOrGroup  regex
 *   cases.tsv   id    expect  text
 *   pii.tsv     id    input   expectedOutput
 */
public class RuleHarness {
    static final Base64.Decoder B64 = Base64.getDecoder();

    record Rule(String kind, String name, int num, Pattern p) {}

    static String d(String s) {
        return new String(B64.decode(s), StandardCharsets.UTF_8);
    }

    public static void main(String[] args) throws Exception {
        Path dir = Path.of(args[0]);
        int threshold = Integer.parseInt(args[1]);
        List<Rule> inj = new ArrayList<>();
        Map<String, Rule> pii = new LinkedHashMap<>();
        Pattern hidden = null;
        for (String line : Files.readAllLines(dir.resolve("rules.tsv"))) {
            String[] f = line.split("\t");
            String kind = d(f[0]), name = d(f[1]), regex = d(f[3]);
            int num = Integer.parseInt(d(f[2]));
            Rule r = new Rule(kind, name, num, Pattern.compile(regex));
            switch (kind) {
                case "INJ" -> inj.add(r);
                case "PII" -> pii.put(name, r);
                case "HIDDEN" -> hidden = r.p();
                default -> throw new IllegalStateException(kind);
            }
        }

        int failures = 0, total = 0;
        System.out.println("== Injection suite (threshold " + threshold + ", " + inj.size() + " rules) ==");
        for (String line : Files.readAllLines(dir.resolve("cases.tsv"))) {
            String[] f = line.split("\t");
            String id = d(f[0]), expect = d(f[1]), text = d(f[2]);
            int score = 0;
            List<String> reasons = new ArrayList<>();
            if (hidden.matcher(text).find()) {
                score += 20;
                reasons.add("hidden_characters");
            }
            String norm = hidden.matcher(text).replaceAll("").toLowerCase().replaceAll("\\s+", " ").trim();
            for (Rule r : inj) {
                if (r.p().matcher(norm).find()) {
                    score += r.num();
                    reasons.add(r.name());
                }
            }
            score = Math.min(score, 100);
            String got = score >= threshold ? "block" : "allow";
            boolean ok = got.equals(expect);
            total++;
            if (!ok) failures++;
            System.out.printf("%s %-8s expect=%-5s got=%-5s score=%3d %s%n", ok ? "PASS" : "FAIL", id, expect, got, score, reasons);
        }

        System.out.println("\n== PII redaction ==");
        String[] order = { "SSN", "SSN_LABELLED", "CARD", "ROUTING", "ACCOUNT", "EMAIL", "PHONE" };
        for (String line : Files.readAllLines(dir.resolve("pii.tsv"))) {
            String[] f = line.split("\t");
            String id = d(f[0]), input = d(f[1]), expected = d(f[2]);
            String text = input;
            for (String name : order) {
                Rule r = pii.get(name);
                text = replace(text, r.p(), r.num(), name.startsWith("SSN") ? "SSN" : name);
            }
            boolean ok = text.equals(expected);
            total++;
            if (!ok) failures++;
            System.out.printf("%s %-8s %s%n", ok ? "PASS" : "FAIL", id, ok ? text : ("\n   got:      " + text + "\n   expected: " + expected));
        }
        System.out.printf("%n%d checks, %d failures%n", total, failures);
        System.exit(failures == 0 ? 0 : 1);
    }

    static String replace(String input, Pattern p, int group, String kind) {
        Matcher m = p.matcher(input);
        StringBuilder sb = new StringBuilder();
        int last = 0;
        boolean any = false;
        while (m.find()) {
            int s = group == 0 ? m.start() : m.start(group);
            int e = group == 0 ? m.end() : m.end(group);
            String value = group == 0 ? m.group() : m.group(group);
            String token = token(kind, value);
            if (token == null) continue;
            sb.append(input, last, s).append(token);
            last = e;
            any = true;
        }
        if (!any) return input;
        sb.append(input.substring(last));
        return sb.toString();
    }

    static String token(String kind, String value) {
        String digits = value.replaceAll("[^0-9]", "");
        String last4 = digits.length() >= 4 ? digits.substring(digits.length() - 4) : digits;
        return switch (kind) {
            case "SSN" -> "[SSN REDACTED]";
            case "CARD" -> (digits.length() < 13 || digits.length() > 19 || !luhn(digits)) ? null : "[CARD ****" + last4 + "]";
            case "ROUTING" -> aba(digits) ? "[ROUTING REDACTED]" : null;
            case "ACCOUNT" -> "[ACCOUNT ****" + last4 + "]";
            case "EMAIL" -> "[EMAIL REDACTED]";
            case "PHONE" -> "[PHONE REDACTED]";
            default -> null;
        };
    }

    static boolean luhn(String digits) {
        int sum = 0;
        boolean dbl = false;
        for (int i = digits.length() - 1; i >= 0; i--) {
            int d = digits.charAt(i) - '0';
            if (dbl) {
                d *= 2;
                if (d > 9) d -= 9;
            }
            sum += d;
            dbl = !dbl;
        }
        return sum > 0 && sum % 10 == 0;
    }

    static boolean aba(String digits) {
        if (digits.length() != 9) return false;
        int[] w = { 3, 7, 1, 3, 7, 1, 3, 7, 1 };
        int sum = 0;
        for (int i = 0; i < 9; i++) sum += (digits.charAt(i) - '0') * w[i];
        return sum > 0 && sum % 10 == 0;
    }
}
