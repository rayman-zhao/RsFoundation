import Foundation

#if os(macOS)
#else
    import FoundationXML

    class XMLParser {
        enum ErrorCode: Error {
            case emptyDocumentError
        }
    }

#endif
extension XMLDocument {
    /// Constructs an XML document from UTF-16 encoded data.
    ///
    /// On Windows, exception will be thrown if xml encoding is not utf-8.
    ///
    /// - Parameters:
    ///   - utf16Data: Data buffer of utf16 encoding.
    ///   - options: Same as init.
    ///
    /// - Throws: Same as init.
    public convenience init(utf16Data: Data, options: XMLNode.Options = []) throws {
        #if os(macOS)
            try self.init(data: utf16Data, options: options)
        #else
            guard !utf16Data.isEmpty else { throw XMLParser.ErrorCode.emptyDocumentError }  // Empty data will crash on Windows even with try.
            let str = String(utf16Data: utf16Data)
            let xml = str.replacing("<?xml version=\"1.0\" encoding=\"unicode\" ?>", with: "<?xml version=\"1.0\" encoding=\"utf-8\" ?>")
            try self.init(xmlString: xml, options: options)
        #endif
    }

    /// Depth first traverse all elements of the XML document.
    ///
    /// Only calls the closure for elements that have attributes.
    ///
    /// - Parameters:
    ///   - root: Start element, default nil for the root element.
    ///   - visitSelf: Whether to visit the root element itself.
    ///   - body: The callback closure.
    public func forEachElement(
        from root: XMLElement? = nil, visitSelf: Bool = true,
        _ body: (_ parent: String, _ name: String, _ attribute: String, _ value: String) -> Void
    ) {
        guard let parent = root ?? rootElement() else { return }

        let pname = parent.name ?? ""
        if visitSelf {
            parent.attributes?.forEach { attr in
                if let aname = attr.name,
                    let aval = attr.stringValue
                {
                    body(pname, pname, aname, aval)
                }
            }
        }

        parent.children?.forEach { node in
            if node.kind == .element,
                let element = node as? XMLElement,
                let ename = element.name
            {
                element.attributes?.forEach { attr in
                    if let aname = attr.name,
                        let aval = attr.stringValue
                    {
                        body(pname, ename, aname, aval)
                    }
                }
                forEachElement(from: element, visitSelf: false, body)
            }
        }
    }
}
