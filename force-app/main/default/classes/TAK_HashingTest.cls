@IsTest
private class TAK_HashingTest {
    @IsTest
    static void canonicalJsonSortsKeysAndNormalisesNumbers() {
        Map<String, Object> a = (Map<String, Object>) JSON.deserializeUntyped('{"b":1,"a":{"y":25000.00,"x":[2,1]}}');
        Map<String, Object> b = (Map<String, Object>) JSON.deserializeUntyped('{"a":{"x":[2,1],"y":25000},"b":1.0}');
        System.assertEquals('{"a":{"x":[2,1],"y":25000},"b":1}', TAK_Hashing.canonicalJson(a));
        System.assertEquals(TAK_Hashing.canonicalJson(a), TAK_Hashing.canonicalJson(b));
    }

    @IsTest
    static void payloadHashBindsActionAndValues() {
        Map<String, Object> p1 = new Map<String, Object>{ 'amount' => 25000, 'to' => '123' };
        Map<String, Object> p2 = new Map<String, Object>{ 'to' => '123', 'amount' => 25000.0 };
        Map<String, Object> p3 = new Map<String, Object>{ 'to' => '123', 'amount' => 25001 };
        System.assertEquals(TAK_Hashing.payloadHash('Initiate_Transfer', p1), TAK_Hashing.payloadHash('initiate_transfer', p2));
        System.assertNotEquals(TAK_Hashing.payloadHash('Initiate_Transfer', p1), TAK_Hashing.payloadHash('Initiate_Transfer', p3));
        System.assertNotEquals(TAK_Hashing.payloadHash('Initiate_Transfer', p1), TAK_Hashing.payloadHash('Other', p1));
    }

    @IsTest
    static void sha256MatchesKnownVector() {
        System.assertEquals(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
            TAK_Hashing.sha256('abc')
        );
        System.assertEquals(64, TAK_Hashing.sha256(null).length());
        System.assertEquals('null', TAK_Hashing.canonicalJson(null));
    }
}
