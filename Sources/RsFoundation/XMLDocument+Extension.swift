import Foundation

#if os(Windows)
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
            let xml = str.replacing(
                "<?xml version=\"1.0\" encoding=\"unicode\" ?>",
                with: "<?xml version=\"1.0\" encoding=\"utf-8\" ?>")
            try self.init(xmlString: xml, options: options)
        #endif
    }

    /// Depth first traverse all elements of the XML document.
    ///
    /// Calls the closure once per attribute of each element; elements without
    /// attributes get a single call with a nil attribute and their text
    /// content as the value.
    ///
    /// - Parameters:
    ///   - root: Start element, default nil for the root element.
    ///   - visitSelf: Whether to visit the root element itself.
    ///   - body: The callback closure.
    public func forEachElement(
        from root: XMLElement? = nil, visitSelf: Bool = true,
        _ body: (_ parent: String, _ name: String, _ attribute: String?, _ value: String?) -> Void
    ) {
        guard let parent = root ?? rootElement() else { return }

        let pname = parent.name ?? ""
        if visitSelf {
            emit(element: parent, ename: pname, pname: pname, body)
        }

        parent.children?.forEach { node in
            if node.kind == .element,
                let element = node as? XMLElement,
                let ename = element.name
            {
                emit(element: element, ename: ename, pname: pname, body)
                forEachElement(from: element, visitSelf: false, body)
            }
        }
    }

    private func emit(
        element: XMLElement, ename: String, pname: String,
        _ body: (_ parent: String, _ name: String, _ attribute: String?, _ value: String?) -> Void
    ) {
        guard let attributes = element.attributes, !attributes.isEmpty else {
            body(pname, ename, nil, textContent(of: element))
            return
        }
        for attr in attributes {
            if let aname = attr.name,
                let aval = attr.stringValue
            {
                body(pname, ename, aname, aval)
            }
        }
    }

    private func textContent(of element: XMLElement) -> String? {
        let text = element.children?
            .compactMap { $0.kind == .text ? $0.stringValue : nil }
            .joined() ?? ""
        return text.isEmpty ? nil : text
    }
}
