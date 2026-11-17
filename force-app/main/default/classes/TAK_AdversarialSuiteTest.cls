/**
 * Runs every case in the TAK_AdversarialPrompts static resource. Add new attacks (and new
 * benign messages that must keep working) to the JSON file; this test picks them up.
 */
@IsTest
private class TAK_AdversarialSuiteTest {
    @IsTest
    static void everyCaseMeetsExpectation() {
        StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = 'TAK_AdversarialPrompts' LIMIT 1];
        Map<String, Object> suite = (Map<String, Object>) JSON.deserializeUntyped(sr.Body.toString());
        Integer threshold = suite.containsKey('threshold') ? Integer.valueOf(suite.get('threshold')) : 50;
        List<Object> cases = (List<Object>) suite.get('cases');
        System.assert(cases.size() >= 30, 'suite should have at least 30 cases');

        List<String> failures = new List<String>();
        Integer attacks = 0;
        Integer benign = 0;
        for (Object o : cases) {
            Map<String, Object> c = (Map<String, Object>) o;
            String id = (String) c.get('id');
            String expect = (String) c.get('expect');
            TAK_InjectionDetector.Result r = TAK_InjectionDetector.scan((String) c.get('text'));
            String got = r.exceeds(threshold) ? 'block' : 'allow';
            if (expect == 'block') {
                attacks++;
            } else {
                benign++;
            }
            if (got != expect) {
                failures.add(id + ' expected ' + expect + ' got ' + got + ' (score ' + r.score + ', ' + r.reasons + ')');
            }
        }
        System.assert(attacks > 0 && benign > 0, 'suite must contain both attacks and benign cases');
        System.assert(failures.isEmpty(), 'Adversarial suite failures:\n' + String.join(failures, '\n'));
    }
}
