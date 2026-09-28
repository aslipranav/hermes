package hk.hku.cecid.piazza.commons.xpath;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Vector;

import javax.xml.XMLConstants;
import javax.xml.namespace.QName;
import javax.xml.xpath.XPathFunctionException;
import javax.xml.xpath.XPathFunctionResolver;

/**
 * Resolves custom functions registered with an XPathExecutor.
 *
 * @author Hugo Y. K. Lam
 */
class XPathFunctionsProvider implements XPathFunctionResolver {

    private final Map<QName, XPathFunction> functions = new HashMap<QName, XPathFunction>();

    /**
     * Registers a function to this provider.
     *
     * @param ns the namespace of the function.
     * @param funcName the function name.
     * @param func the function implementation.
     */
    public void regsiterFunction(String ns, String funcName, XPathFunction func) {
        if (funcName != null && !funcName.trim().isEmpty() && func != null) {
            String namespace = ns == null ? XMLConstants.NULL_NS_URI : ns.trim();
            functions.put(new QName(namespace, funcName.trim()), func);
        }
    }

    @Override
    public javax.xml.xpath.XPathFunction resolveFunction(QName functionName, int arity) {
        final XPathFunction function = functions.get(functionName);
        if (function == null) {
            return null;
        }
        return new javax.xml.xpath.XPathFunction() {
            @Override
            public Object evaluate(List<?> arguments) throws XPathFunctionException {
                try {
                    return function.execute(new Vector<Object>(arguments));
                }
                catch (Exception e) {
                    throw new XPathFunctionException(e);
                }
            }
        };
    }
}
