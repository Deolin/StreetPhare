package javax.lang.model;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Shim Android pour {@code javax.lang.model.SourceVersion}.
 *
 * <p>GraphHopper Core 7.0 (bibliothèque JVM) appelle {@code SourceVersion.isKeyword(CharSequence)}
 * dans {@code IntEncodedValueImpl.isValidEncodedValue()} pour valider les noms d'EncodedValue
 * (cf. issue graphhopper#2735). Cette classe appartient au module {@code java.compiler},
 * absent du runtime Android, ce qui provoquait :
 *
 * <pre>
 * java.lang.NoClassDefFoundError: Failed resolution of: Ljavax/lang/model/SourceVersion;
 * </pre>
 *
 * <p>Ce substitut fournit le sous-ensemble d'helpers statiques utilisés par GraphHopper,
 * sans dépendance au module compilateur.</p>
 */
public final class SourceVersion {

    private SourceVersion() {
        // Non instantiable : seule l'API statique est utilisée par GraphHopper.
    }

    /**
     * Mots-clés du langage Java (Java 8 → 17), identiques à la liste conservée
     * par GraphHopper avant le passage à {@code SourceVersion.isKeyword()}.
     */
    private static final Set<String> KEYWORDS = new HashSet<>(Arrays.asList(
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
            "class", "const", "continue", "default", "do", "double", "else", "enum",
            "extends", "false", "final", "finally", "float", "for", "goto", "if",
            "implements", "import", "instanceof", "int", "interface", "long", "native",
            "new", "non-sealed", "null", "package", "permits", "private", "protected",
            "public", "record", "return", "sealed", "short", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws", "transient",
            "true", "try", "var", "void", "volatile", "while", "yield", "_"
    ));

    /** Renvoie {@code true} si {@code s} est un mot-clé du langage Java. */
    public static boolean isKeyword(CharSequence s) {
        return s != null && KEYWORDS.contains(s.toString());
    }

    /** Renvoie {@code true} si {@code s} est un identifiant Java valide. */
    public static boolean isIdentifier(CharSequence s) {
        if (s == null || s.length() == 0) {
            return false;
        }
        if (!Character.isJavaIdentifierStart(s.charAt(0))) {
            return false;
        }
        for (int i = 1; i < s.length(); i++) {
            if (!Character.isJavaIdentifierPart(s.charAt(i))) {
                return false;
            }
        }
        return true;
    }

    /** Renvoie {@code true} si {@code s} est un nom Java valide (identifiant ou mot-clé). */
    public static boolean isName(CharSequence s) {
        return isIdentifier(s) || isKeyword(s);
    }
}
