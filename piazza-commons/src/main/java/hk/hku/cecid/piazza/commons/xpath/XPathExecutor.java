package hk.hku.cecid.piazza.commons.xpath;

import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.Set;

import javax.xml.XMLConstants;
import javax.xml.namespace.NamespaceContext;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.TransformerException;
import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathEvaluationResult;
import javax.xml.xpath.XPathExpressionException;
import javax.xml.xpath.XPathFactory;

import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

/**
 * XPathExecutor evaluates XPath expressions using the supported JAXP API.
 *
 * @author Hugo Y. K. Lam
 */
public class XPathExecutor {

    private final Node contextNode;
    private final XPathFunctionsProvider functionsProvider;
    private final NamespaceContext namespaceContext;

    /**
     * Creates a new instance of XPathExecutor.
     */
    public XPathExecutor() {
        this(null);
    }

    /**
     * Creates a new instance of XPathExecutor.
     *
     * @param document the document containing the context being queried and
     *                 the namespaces being referenced.
     */
    public XPathExecutor(Node document) {
        this(document, null);
    }

    /**
     * Creates a new instance of XPathExecutor.
     *
     * @param context the document containing the context being queried.
     * @param namespaces the document containing the namespaces being referenced.
     */
    public XPathExecutor(Node context, Node namespaces) {
        this.contextNode = context == null ? createDocument() : context;
        Node namespaceNode = namespaces == null ? contextNode : namespaces;
        this.functionsProvider = new XPathFunctionsProvider();
        this.namespaceContext = new NodeNamespaceContext(namespaceNode);
    }

    /**
     * Registers a function to be used in an XPath.
     *
     * @param ns the namespace of the function.
     * @param funcName the function name.
     * @param func the function implementation.
     */
    public void registerFunction(String ns, String funcName, XPathFunction func) {
        functionsProvider.regsiterFunction(ns, funcName, func);
    }

    /**
     * Evaluates an XPath expression.
     *
     * @param expression the XPath expression.
     * @return the evaluated result.
     * @throws TransformerException if unable to transform the expression.
     */
    public Object eval(String expression) throws TransformerException {
        return eval(expression, null);
    }

    /**
     * Evaluates an XPath expression.
     *
     * @param expression the XPath expression.
     * @param context the document containing the context being queried.
     * @return the evaluated result.
     * @throws TransformerException if unable to transform the expression.
     */
    public Object eval(String expression, Node context) throws TransformerException {
        Node evaluationContext = context == null ? contextNode : context;
        try {
            XPathEvaluationResult<?> result = createXPath().evaluateExpression(expression, evaluationContext);
            return result.value();
        }
        catch (XPathExpressionException e) {
            throw new TransformerException("Cannot evaluate XPath expression", e);
        }
    }

    private XPath createXPath() {
        // Bundled Xalan only implements the older, explicitly typed XPath API.
        XPath xpath = XPathFactory.newDefaultInstance().newXPath();
        xpath.setNamespaceContext(namespaceContext);
        xpath.setXPathFunctionResolver(functionsProvider);
        return xpath;
    }

    private static Node createDocument() {
        try {
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            DocumentBuilder builder = factory.newDocumentBuilder();
            return builder.newDocument();
        }
        catch (Exception e) {
            throw new IllegalStateException("Cannot construct or configure document builder", e);
        }
    }

    private static final class NodeNamespaceContext implements NamespaceContext {
        private final Node namespaceNode;

        private NodeNamespaceContext(Node namespaceNode) {
            this.namespaceNode = namespaceNode;
        }

        @Override
        public String getNamespaceURI(String prefix) {
            if (prefix == null) {
                throw new IllegalArgumentException("Prefix must not be null");
            }
            if (XMLConstants.XML_NS_PREFIX.equals(prefix)) {
                return XMLConstants.XML_NS_URI;
            }
            if (XMLConstants.XMLNS_ATTRIBUTE.equals(prefix)) {
                return XMLConstants.XMLNS_ATTRIBUTE_NS_URI;
            }
            String namespace = namespaceNode.lookupNamespaceURI(prefix.isEmpty() ? null : prefix);
            return namespace == null ? XMLConstants.NULL_NS_URI : namespace;
        }

        @Override
        public String getPrefix(String namespaceURI) {
            Iterator<String> prefixes = getPrefixes(namespaceURI);
            return prefixes.hasNext() ? prefixes.next() : null;
        }

        @Override
        public Iterator<String> getPrefixes(String namespaceURI) {
            if (namespaceURI == null) {
                throw new IllegalArgumentException("Namespace URI must not be null");
            }
            Set<String> prefixes = new LinkedHashSet<String>();
            Node node = namespaceNode.getNodeType() == Node.DOCUMENT_NODE
                    ? ((Document) namespaceNode).getDocumentElement() : namespaceNode;
            for (; node != null; node = node.getParentNode()) {
                NamedNodeMap attributes = node.getAttributes();
                if (attributes == null) {
                    continue;
                }
                for (int i = 0; i < attributes.getLength(); i++) {
                    Node attribute = attributes.item(i);
                    if (!namespaceURI.equals(attribute.getNodeValue())) {
                        continue;
                    }
                    String name = attribute.getNodeName();
                    if (XMLConstants.XMLNS_ATTRIBUTE.equals(name)) {
                        prefixes.add(XMLConstants.DEFAULT_NS_PREFIX);
                    }
                    else if (name.startsWith(XMLConstants.XMLNS_ATTRIBUTE + ":")) {
                        prefixes.add(name.substring(XMLConstants.XMLNS_ATTRIBUTE.length() + 1));
                    }
                }
            }
            return prefixes.isEmpty() ? Collections.<String>emptySet().iterator() : prefixes.iterator();
        }
    }
}
