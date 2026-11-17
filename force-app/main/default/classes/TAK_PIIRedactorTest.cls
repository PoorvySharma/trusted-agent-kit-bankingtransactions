@IsTest
private class TAK_PIIRedactorTest {
    @IsTest
    static void redactsFormattedAndLabelledSsn() {
        System.assertEquals('My SSN is [SSN REDACTED].', TAK_PIIRedactor.mask('My SSN is 123-45-6789.'));
        System.assertEquals('ssn: [SSN REDACTED]', TAK_PIIRedactor.mask('ssn: 123456789'));
    }

    @IsTest
    static void ignoresInvalidSsnRanges() {
        System.assertEquals('Order 000-12-3456 ok', TAK_PIIRedactor.mask('Order 000-12-3456 ok'));
    }

    @IsTest
    static void redactsOnlyLuhnValidCards() {
        System.assertEquals('Card [CARD ****1111] declined', TAK_PIIRedactor.mask('Card 4111 1111 1111 1111 declined'));
        System.assertEquals('Card 4111 1111 1111 1112 typo', TAK_PIIRedactor.mask('Card 4111 1111 1111 1112 typo'));
        System.assertEquals('Amex [CARD ****0005]', TAK_PIIRedactor.mask('Amex 3782 822463 10005'));
    }

    @IsTest
    static void redactsRoutingAndAccountNumbersInJson() {
        String input = '{"routingNumber":"021000021","accountNumber":"000123456789"}';
        String expected = '{"routingNumber":"[ROUTING REDACTED]","accountNumber":"[ACCOUNT ****6789]"}';
        TAK_PIIRedactor.Result res = TAK_PIIRedactor.redact(input);
        System.assertEquals(expected, res.text);
        System.assertEquals(1, res.counts.get('ROUTING'));
        System.assertEquals(1, res.counts.get('ACCOUNT'));
        System.assertEquals(2, res.total());
    }

    @IsTest
    static void redactsEmailAndPhoneButNotAmountsOrDates() {
        System.assertEquals(
            'Reach me at [EMAIL REDACTED] or [PHONE REDACTED]',
            TAK_PIIRedactor.mask('Reach me at jane.doe@example.com or (312) 555-0199')
        );
        System.assertEquals(
            'Call [PHONE REDACTED] about the $25,000.00 wire on 2026-11-06',
            TAK_PIIRedactor.mask('Call 312-555-0199 about the $25,000.00 wire on 2026-11-06')
        );
    }

    @IsTest
    static void handlesBlankAndLongInput() {
        System.assertEquals(null, TAK_PIIRedactor.mask(null));
        System.assertEquals('', TAK_PIIRedactor.mask(''));
        String longText = 'a'.repeat(TAK_PIIRedactor.MAX_INPUT_LENGTH + 50);
        System.assertEquals(TAK_PIIRedactor.MAX_INPUT_LENGTH, TAK_PIIRedactor.mask(longText).length());
    }

    @IsTest
    static void checksumHelpers() {
        System.assert(TAK_PIIRedactor.passesLuhn('4111111111111111'));
        System.assert(!TAK_PIIRedactor.passesLuhn('4111111111111112'));
        System.assert(TAK_PIIRedactor.passesAbaChecksum('021000021'));
        System.assert(!TAK_PIIRedactor.passesAbaChecksum('123456789'));
        System.assert(!TAK_PIIRedactor.passesAbaChecksum('12345'));
    }
}
