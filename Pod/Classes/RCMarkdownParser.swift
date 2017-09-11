import Foundation
import UIKit

private let nonBreakingSpaceCharacter = Character("\u{00A0}")

public struct RCMarkdownRegex {
    public static let CodeEscaping = "(?<!\\\\)(?:\\\\\\\\)*+(`+)(.*?[^`].*?)(\\1)(?!`)"
    public static let Escaping = "\\\\."
    public static let Unescaping = "\\\\[0-9a-z]{4}"
    
    public static let Header = "^(#{1,%@})\\s+(.+)$"
    public static let ShortHeader = "^(#{1,%@})\\s*([^#].*)$"
    public static let List = "^( {0,%@})[\\*\\+\\-]\\s+(.+)$"
    public static let ShortList = "^( {0,%@})[\\*\\+\\-]\\s+([^\\*\\+\\-].*)$"
    public static let NumberedList = "^( {0,})[0-9]+\\.\\s(.+)$"
    public static let Quote = "^(\\>{1,%@})\\s+(.+)$"
    public static let ShortQuote = "^(\\>{1,%@})\\s*([^\\>].*)$"

    public static var allowedSchemes = ["http", "https"]
    fileprivate static var _allowedSchemes: String {
        return allowedSchemes.joined(separator: "|")
    }
    
    public static let Image = "!\\[([^\\]]+)\\]\\(((?:\(_allowedSchemes)):\\/\\/[^\\)]+)\\)"
    public static let ImageOptions: NSRegularExpression.Options = [.anchorsMatchLines]
    public static let Link = "\\[([^\\]]+)\\]\\(((?:http|https):\\/\\/[^\\)]+)\\)"
    public static let LinkOptions: NSRegularExpression.Options = [.anchorsMatchLines]
    
    public static let Monospace = "(`+)(\\s*.*?[^`]\\s*)(\\1)(?!`)"
    public static let Strong = "(?:^|&gt;|[ >_~`])(\\*{1,2})([^\\*\r\n]+)(\\*{1,2})(?:[<_~`]|\\B|\\b|$)"
    public static let StrongOptions: NSRegularExpression.Options = [.anchorsMatchLines]
    public static let Italic = "(?:^|&gt;|[ >*~`])(\\_{1,2})([^\\_\r\n]+)(\\_{1,2})(?:[<*~`]|\\B|\\b|$)"
    public static let ItalicOptions: NSRegularExpression.Options = [.anchorsMatchLines]
    public static let Strike = "(?:^|&gt;|[ >_*`])(\\~{1,2})([^~\r\n]+)(\\~{1,2})(?:[<_*`]|\\B|\\b|$)"
    public static let StrikeOptions: NSRegularExpression.Options = [.anchorsMatchLines]
    
    public static func regexForString(_ regexString: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: regexString, options: options)
        } catch {
            return nil
        }
    }
}

open class RCMarkdownParser: RCBaseParser {
    
    public typealias RCMarkdownParserFormattingBlock = ((NSMutableAttributedString, NSRange) -> Void)
    public typealias RCMarkdownParserLevelFormattingBlock = ((NSMutableAttributedString, NSRange, Int) -> Void)
    
    open var headerAttributes = [[String: Any]]()
    open var listAttributes = [[String: Any]]()
    open var numberedListAttributes = [[String: Any]]()
    open var quoteAttributes = [[String: Any]]()
    
    open var imageAttributes = [String: Any]()
    open var linkAttributes = [String: Any]()
    open var monospaceAttributes = [String: Any]()
    open var strongAttributes = [String: Any]()
    open var italicAttributes = [String: Any]()
    open var strongAndItalicAttributes = [String: Any]()
    open var strikeAttributes = [String: Any]()

    public typealias DownloadImageClosure = (UIImage?)->Void
    open var downloadImage: (_ path: String, _ completion: DownloadImageClosure?) -> Void = {
        _,completion in
        completion?(nil)
    }
    
    open static var standardParser = RCMarkdownParser()
    
    class func addAttributes(_ attributesArray: [[String: Any]], atIndex level: Int, toString attributedString: NSMutableAttributedString, range: NSRange) {
        guard !attributesArray.isEmpty else { return }
        
        guard let newAttributes = level < attributesArray.count && level >= 0 ? attributesArray[level] : attributesArray.last else { return }
        
        attributedString.addAttributes(newAttributes, range: range)
    }
    
    public init(withDefaultParsing: Bool = true) {
        super.init()
        
        strongAttributes = [NSFontAttributeName: UIFont.boldSystemFont(ofSize: 12)]
        italicAttributes = [NSFontAttributeName: UIFont.italicSystemFont(ofSize: 12)]
        
        var strongAndItalicFont = UIFont.systemFont(ofSize: 12)
        strongAndItalicFont = UIFont(descriptor: strongAndItalicFont.fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold])!, size: strongAndItalicFont.pointSize)
        strongAndItalicAttributes = [NSFontAttributeName: strongAndItalicFont]
        
        if withDefaultParsing {
            addStrongParsingWithFormattingBlock { attributedString, range in
                attributedString.enumerateAttributes(in: range, options: []) { attributes, range, _ in
                    if let font = attributes[NSFontAttributeName] as? UIFont, let italicFont = self.italicAttributes[NSFontAttributeName] as? UIFont, font == italicFont {
                        attributedString.addAttributes(self.strongAndItalicAttributes, range: range)
                    } else {
                        attributedString.addAttributes(self.strongAttributes, range: range)
                    }
                }
            }

            addItalicParsingWithFormattingBlock { attributedString, range in
                attributedString.enumerateAttributes(in: range, options: []) { attributes, range, _ in
                    if let font = attributes[NSFontAttributeName] as? UIFont, let boldFont = self.strongAttributes[NSFontAttributeName] as? UIFont, font == boldFont {
                        attributedString.addAttributes(self.strongAndItalicAttributes, range: range)
                    } else {
                        attributedString.addAttributes(self.italicAttributes, range: range)
                    }
                }
            }

            addStrikeParsingWithFormattingBlock { attributedString, range in
                attributedString.addAttributes(self.strikeAttributes, range: range)
            }

            addImageParsingWithImageFormattingBlock({ attributedString, range in
                attributedString.addAttributes(self.imageAttributes, range: range)
            }, alternativeTextFormattingBlock: { attributedString, range in
                attributedString.addAttributes(self.imageAttributes, range: range)
            })

            addLinkDetectionWithFormattingBlock { attributedString, range in
                attributedString.addAttributes(self.linkAttributes, range: range)
            }
        }
    }
    
    open func addEscapingParsing() {
        guard let escapingRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.Escaping) else { return }
        
        addParsingRuleWithRegularExpression(escapingRegex) { match, attributedString in
            let range = NSRange(location: match.range.location + 1, length: 1)
            let matchString = attributedString.attributedSubstring(from: range).string as NSString
            let escapedString = NSString(format: "%04x", matchString.character(at: 0)) as String
            attributedString.replaceCharacters(in: range, with: escapedString)
        }
    }
    
    open func addCodeEscapingParsing() {
        guard let codingParsingRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.CodeEscaping) else { return }
        
        addParsingRuleWithRegularExpression(codingParsingRegex) { match, attributedString in
            let range = match.rangeAt(2)
            let matchString = attributedString.attributedSubstring(from: range).string as NSString
            
            var escapedString = ""
            for index in 0..<range.length {
                escapedString = "\(escapedString)\(NSString(format: "%04x", matchString.character(at: index)))"
            }

            attributedString.replaceCharacters(in: range, with: escapedString)
        }
    }
    
    fileprivate func addLeadParsingWithPattern(_ pattern: String, maxLevel: Int?, leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        let regexString: String = {
            let maxLevel: Int = maxLevel ?? 0
            return NSString(format: pattern as NSString, maxLevel > 0 ? "\(maxLevel)" : "") as String
        }()
        
        guard let regex = RCMarkdownRegex.regexForString(regexString, options: .anchorsMatchLines) else { return }
        
        addParsingRuleWithRegularExpression(regex) { match, attributedString in
            let level = match.rangeAt(1).length
            formattingBlock?(attributedString, match.rangeAt(2), level)
            leadFormattingBlock(attributedString, NSRange(location: match.rangeAt(1).location, length: match.rangeAt(2).location - match.rangeAt(1).location), level)
        }
    }
    
    open func addHeaderParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.Header, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addListParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.List, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addNumberedListParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.NumberedList, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addQuoteParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.Quote, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addShortHeaderParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.ShortHeader, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addShortListParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.ShortList, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addShortQuoteParsingWithLeadFormattingBlock(_ leadFormattingBlock: @escaping RCMarkdownParserLevelFormattingBlock, maxLevel: Int? = nil, textFormattingBlock formattingBlock: RCMarkdownParserLevelFormattingBlock?) {
        addLeadParsingWithPattern(RCMarkdownRegex.ShortQuote, maxLevel: maxLevel, leadFormattingBlock: leadFormattingBlock, formattingBlock: formattingBlock)
    }
    
    open func addImageParsingWithImageFormattingBlock(_ formattingBlock: RCMarkdownParserFormattingBlock?, alternativeTextFormattingBlock alternateFormattingBlock: RCMarkdownParserFormattingBlock?) {
        guard let headerRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.Image, options: RCMarkdownRegex.ImageOptions) else { return }
        
        addParsingRuleWithRegularExpression(headerRegex) { match, attributedString in
            let imagePathStart = (attributedString.string as NSString).range(of: "(", options: [], range: match.range).location
            let linkRange = NSRange(location: imagePathStart, length: match.range.length + match.range.location - imagePathStart - 1)
            let imagePath = (attributedString.string as NSString).substring(with: NSRange(location: linkRange.location + 1, length: linkRange.length - 1))

            self.downloadImage(imagePath) { image in
                if let image = image {
                    let imageAttatchment = NSTextAttachment()
                    imageAttatchment.image = image
                    imageAttatchment.bounds = CGRect(x: 0, y: -5, width: image.size.width, height: image.size.height)
                    let imageString = NSAttributedString(attachment: imageAttatchment)
                    attributedString.replaceCharacters(in: match.range, with: imageString)
                    formattingBlock?(attributedString, NSRange(location: match.range.location, length: imageString.length))
                } else {
                    let linkTextEndLocation = (attributedString.string as NSString).range(of: "]", options: [], range: match.range).location
                    let linkTextRange = NSRange(location: match.range.location + 2, length: linkTextEndLocation - match.range.location - 2)
                    let alternativeText = (attributedString.string as NSString).substring(with: linkTextRange)
                    attributedString.replaceCharacters(in: match.range, with: alternativeText)
                    alternateFormattingBlock?(attributedString, NSRange(location: match.range.location, length: (alternativeText as NSString).length))
                }
            }
        }
    }
    
    open func addLinkParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        guard let linkRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.Link, options: RCMarkdownRegex.LinkOptions) else { return }
        
        addParsingRuleWithRegularExpression(linkRegex) { [weak self] match, attributedString in
            let linkStartinResult = (attributedString.string as NSString).range(of: "(", options: .backwards, range: match.range).location
            let linkRange = NSRange(location: linkStartinResult, length: match.range.length + match.range.location - linkStartinResult - 1)
            let linkUrlString = (attributedString.string as NSString).substring(with: NSRange(location: linkRange.location + 1, length: linkRange.length - 1))
            
            let linkTextRange = NSRange(location: match.range.location + 1, length: linkStartinResult - match.range.location - 2)
            attributedString.deleteCharacters(in: NSRange(location: linkRange.location - 1, length: linkRange.length + 2))
            
            if let linkUrlString = self?.unescaped(string: linkUrlString), let url = URL(string: linkUrlString) ?? URL(string: linkUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? linkUrlString) {
                attributedString.addAttribute(NSLinkAttributeName, value: url, range: linkTextRange)
            }
            formattingBlock(attributedString, linkTextRange)
            
            attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: 1))
        }
    }
    
    fileprivate func addEnclosedParsingWithPattern(_ pattern: String, options: NSRegularExpression.Options = [], formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        guard let regex = RCMarkdownRegex.regexForString(pattern) else { return }
        
        addParsingRuleWithRegularExpression(regex) { match, attributedString in
            attributedString.deleteCharacters(in: match.rangeAt(3))
            formattingBlock(attributedString, match.rangeAt(2))
            attributedString.deleteCharacters(in: match.rangeAt(1))
        }
    }
    
    open func addMonospacedParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        addEnclosedParsingWithPattern(RCMarkdownRegex.Monospace, formattingBlock: formattingBlock)
    }
    
    open func addStrongParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        addEnclosedParsingWithPattern(RCMarkdownRegex.Strong, options: RCMarkdownRegex.StrongOptions, formattingBlock: formattingBlock)
    }
    
    open func addItalicParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        addEnclosedParsingWithPattern(RCMarkdownRegex.Italic, options: RCMarkdownRegex.ItalicOptions, formattingBlock: formattingBlock)
    }

    open func addStrikeParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        addEnclosedParsingWithPattern(RCMarkdownRegex.Strike, options: RCMarkdownRegex.StrikeOptions, formattingBlock: formattingBlock)
    }

    open func addLinkDetectionWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        do {
            let linkDataDetector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            addParsingRuleWithRegularExpression(linkDataDetector) { [weak self] match, attributedString in
                if let urlString = match.url?.absoluteString.removingPercentEncoding, let unescapedUrlString = self?.unescaped(string: urlString), let url = URL(string: unescapedUrlString) {
                    attributedString.addAttribute(NSLinkAttributeName, value: url, range: match.range)
                }
                formattingBlock(attributedString, match.range)
            }
        } catch { }
    }
    
    func unescaped(string: String) -> String? {
        guard let unescapingRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.Unescaping, options: .dotMatchesLineSeparators) else { return nil }
        
        var location = 0
        let unescapedMutableString = NSMutableString(string: string)
        while let match = unescapingRegex.firstMatch(in: unescapedMutableString as String, options: .withoutAnchoringBounds, range: NSRange(location: location, length: unescapedMutableString.length - location)) {
            let oldLength = unescapedMutableString.length
            let range = NSRange(location: match.range.location + 1, length: 4)
            let matchString = unescapedMutableString.substring(with: range)
            let unescapedString = RCMarkdownParser.stringWithHexaString(matchString, atIndex: 0)
            unescapedMutableString.replaceCharacters(in: match.range, with: unescapedString)
            let newLength = unescapedMutableString.length
            location = match.range.location + match.range.length + newLength - oldLength
        }
        
        return unescapedMutableString as String
    }
    
    fileprivate class func stringWithHexaString(_ hexaString: String, atIndex index: Int) -> String {
        let range = hexaString.characters.index(hexaString.startIndex, offsetBy: index)..<hexaString.characters.index(hexaString.startIndex, offsetBy: index + 4)
        let sub = hexaString.substring(with: range)
        
        let char = Character(UnicodeScalar(Int(strtoul(sub, nil, 16)))!)
        return "\(char)"
    }
    
    open func addCodeUnescapingParsingWithFormattingBlock(_ formattingBlock: @escaping RCMarkdownParserFormattingBlock) {
        addEnclosedParsingWithPattern(RCMarkdownRegex.CodeEscaping) { attributedString, range in
            let matchString = attributedString.attributedSubstring(from: range).string
            var unescapedString = ""
            for index in 0..<range.length {
                guard index * 4 < range.length else { break }
                
                unescapedString = "\(unescapedString)\(RCMarkdownParser.stringWithHexaString(matchString, atIndex: index * 4))"
            }
            attributedString.replaceCharacters(in: range, with: unescapedString)
            formattingBlock(attributedString, NSRange(location: range.location, length: (unescapedString as NSString).length))
        }
    }
    
    open func addUnescapingParsing() {
        guard let unescapingRegex = RCMarkdownRegex.regexForString(RCMarkdownRegex.Unescaping, options: .dotMatchesLineSeparators) else { return }
        
        addParsingRuleWithRegularExpression(unescapingRegex) { match, attributedString in
            let range = NSRange(location: match.range.location + 1, length: 4)
            let matchString = attributedString.attributedSubstring(from: range).string
            let unescapedString = RCMarkdownParser.stringWithHexaString(matchString, atIndex: 0)
            attributedString.replaceCharacters(in: match.range, with: unescapedString)
        }
    }
    
}
