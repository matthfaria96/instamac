public class TableCheck {
    static int fails = 0;
    public static void main(String[] args) throws Exception {
        Class<?> c = Class.forName("com.instamac.repro.StringTable");
        java.lang.reflect.Method m = c.getMethod("table", int.class);
        check(m, 0, "s0");
        check(m, 1, "s1");
        check(m, 1999, "s1999");
        check(m, 2000, "s2000");
        check(m, 5999, "s5999");
        check(m, 6000, "s6000");
        check(m, 7999, "s7999");
        check(m, -1, "default");
        check(m, 8000, "default");
        if (fails > 0) { System.out.println("FALHAS: " + fails); System.exit(1); }
        System.out.println("OK: 9 casos conferidos, verificacao -Xverify:all passou");
    }
    static void check(java.lang.reflect.Method m, int key, String want) throws Exception {
        Object got = m.invoke(null, key);
        boolean ok = want.equals(got);
        if (!ok) fails++;
        System.out.println((ok ? "  ok   " : "  FALHA") + " table(" + key + ") = " + got
                + (ok ? "" : " (esperado " + want + ")"));
    }
}
