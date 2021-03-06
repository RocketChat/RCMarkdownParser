//
//  RichTextViewController.swift
//  NumberedLists
//
//  Created by Rhett Rogers on 3/7/16.
//  Copyright © 2016 LyokoTech. All rights reserved.
//

import UIKit

open class RichTextViewController: UIViewController {

    static let afterNumberCharacter = "."
    static let spaceAfterNumberCharacter = "\u{00A0}"
    public static let bulletedLineStarter = "\u{2022}\u{00A0}"
    public static var numberedListTrailer: String = {
        return "\(afterNumberCharacter)\(spaceAfterNumberCharacter)"
    }()

    var previousSelection = NSRange()

    open var textView = UITextView()

    open var regularFont: UIFont?
    open var boldFont: UIFont?
    open var italicFont: UIFont?
    open var boldItalicFont: UIFont?

    fileprivate var disableBold = false
    fileprivate var disableItalic = false

    fileprivate var previousTypingAttributes: [NSAttributedString.Key: Any]?

    fileprivate var defaultParagraphStyle: NSParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = 0
        
        return paragraphStyle
    }()
    fileprivate var defaultListParagraphStyle: NSParagraphStyle = {
        let listParagraphStyle = NSMutableParagraphStyle()
        listParagraphStyle.firstLineHeadIndent = 7
        listParagraphStyle.headIndent = 7
        
        return listParagraphStyle
    }()

    fileprivate var defaultListAttributes: [NSAttributedString.Key: Any]? {
        guard let regularFont = regularFont else { return nil }
        
        var listAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.font: regularFont,
            NSAttributedString.Key.paragraphStyle: defaultListParagraphStyle
        ]

        if let textColor = textView.typingAttributes[NSAttributedString.Key.foregroundColor] {
            listAttributes[NSAttributedString.Key.foregroundColor] = textColor
        }

        return listAttributes
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged), name: UITextView.textDidChangeNotification, object: nil)
    }
    
    /// Replaces text in a range with text in parameter
    ///
    /// - parameter range: The range at which to replace the string.
    /// - parameter withText: The text that will be inserted.
    /// - parameter inTextView: The textView in which changes will occur.
    fileprivate func replaceTextInRange(_ range: NSRange, withText replacementText: String, inTextView textView: UITextView) {
        let substringLength = (textView.text as NSString).substring(with: range).length
        let lengthDifference = substringLength - replacementText.length
        let previousRange = textView.selectedRange
        let attributes = textView.attributedText.attributes(at: range.location, effectiveRange: nil)

        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacementText, attributes: attributes))
        textView.textStorage.endEditing()

        let offset = lengthDifference - (previousRange.location - textView.selectedRange.location)
        textView.selectedRange.location -= offset

        textViewDidChangeSelection(textView)
    }

    /// Removes text from a textView at a specified index
    ///
    /// - parameter range: The range of the text to remove.
    /// - parameter toTextView: The `UITextView` to remove the text from.
    fileprivate func removeTextFromRange(_ range: NSRange, fromTextView textView: UITextView, applyDefault: Bool = true) {
        let substringLength = (textView.text as NSString).substring(with: range).length
        let initialRange = textView.selectedRange
        
        if applyDefault {
            applyDefaultParagraphStyleToSelectedRange(range)
        }
        
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
        textView.textStorage.endEditing()

        if range.comesBeforeRange(textView.selectedRange) {
            textView.selectedRange.location -= (substringLength - (initialRange.location - textView.selectedRange.location))
            textView.selectedRange.length = initialRange.length
        } else if range.containedInRange(textView.selectedRange) {
            textView.selectedRange.length -= (substringLength - (initialRange.length - textView.selectedRange.length))
        } else if range.location == textView.selectedRange.location && range.length == textView.selectedRange.length {
            textView.selectedRange.length = 0
        }

        textViewDidChangeSelection(textView)
    }

    /// Apply the default paragraph style (remove list paragraph style) from after the \n previous to the selected area to before the \n past the selected area
    func applyDefaultParagraphStyleToSelectedRange(_ selectedRange: NSRange) {
        let previousNewLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: selectedRange.location) ?? 0
        let nextNewLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: selectedRange.location + selectedRange.length) ?? textView.text.length
        let fullChangeRange = NSRange(location: previousNewLineIndex, length: nextNewLineIndex - previousNewLineIndex)
        
        textView.textStorage.beginEditing()
        textView.textStorage.addAttribute(NSAttributedString.Key.paragraphStyle, value: defaultParagraphStyle, range: fullChangeRange)
        textView.textStorage.endEditing()
        
        if textView.selectedRange.endLocation == textView.text.length {
            textView.typingAttributes[NSAttributedString.Key.paragraphStyle] = defaultParagraphStyle
        }
    }
    
    /// Adds text to a textView at a specified index
    ///
    /// - parameter text: The text to add.
    /// - parameter toTextView: The `UITextView` to add the text to.
    /// - parameter atIndex: The index to insert the text at.
    /// - parameter withAttributes: Optional.  Attributes to apply to the added text.  Will use attributes at the index otherwise.
    fileprivate func addText(_ text: String, toTextView textView: UITextView, atIndex index: Int) {
        previousTypingAttributes = textView.typingAttributes
        
        let attributes: [NSAttributedString.Key: Any] = defaultListAttributes ?? (index < textView.text.length ? textView.attributedText.attributes(at: index, effectiveRange: nil) : textView.typingAttributes)
        textView.textStorage.beginEditing()
        textView.textStorage.insert(NSAttributedString(string: text, attributes: attributes), at: index)
        textView.textStorage.endEditing()

        if textView.selectedRange.location <= index && index < textView.selectedRange.endLocation && textView.selectedRange.length > 0 {
            textView.selectedRange.length += text.length
        } else if index <= textView.selectedRange.location {
            textView.selectedRange.location += text.length
        }
        
        textView.typingAttributes = previousTypingAttributes ?? textView.typingAttributes
        textViewDidChangeSelection(textView)
    }

    /// Toggles a numbered list on the current line if there is a zero-length selection;
    /// else removes all numbered lists in selection if they exist
    /// or adds them to each line if there are no numbered lists in selection
    open func toggleNumberedList() {
        if selectionContainsBulletedList(textView.selectedRange) {
            toggleBulletedList()
        }

        if textView.selectedRange.length == 0 {
            if selectionContainsNumberedList(textView.selectedRange) {
                if let newLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: textView.selectedRange.location), let previousNumber = previousNumberOfNumberedList(textView.selectedRange) {
                    let range = NSRange(location: newLineIndex + 1, length: "\(previousNumber)\(RichTextViewController.numberedListTrailer)".length)
                    removeTextFromRange(range, fromTextView: textView)
                } else {
                    removeTextFromRange(NSRange(location: 0, length: RichTextViewController.numberedListTrailer.length + 1), fromTextView: textView)
                }
            } else {
                if let newLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: textView.selectedRange.location) {
                    let newNumber = (previousNumberOfNumberedList(textView.selectedRange) ?? 0) + 1
                    let insertString = "\(newNumber)\(RichTextViewController.numberedListTrailer)"
                    addText(insertString, toTextView: textView, atIndex: newLineIndex + 1)
                } else {
                    let insertString = "1\(RichTextViewController.numberedListTrailer)"
                    addText(insertString, toTextView: textView, atIndex: 0)
                }
            }
        } else {
            var numbersInSelection = false

            if selectionContainsNumberedList(NSRange(location: textView.selectedRange.location, length: 0)), let range = previousNumberedRangeFromIndex(textView.selectedRange.location, inString: textView.text) {
                numbersInSelection = true
                removeTextFromRange(range, fromTextView: textView)
            }

            if selectionContainsNumberedList(textView.selectedRange) {
                numbersInSelection = true
                var index = textView.selectedRange.location
                while index < textView.text.length {
                    guard let newRange = nextNumberedRangeFromIndex(index, inString: textView.text), newRange.location < textView.selectedRange.endLocation &&
                            newRange.endLocation < textView.text.length &&
                            newRange.length > -1
                        else {
                            break
                    }
                    removeTextFromRange(newRange, fromTextView: textView)
                    index = newRange.location
                }
            }

            if !numbersInSelection {
                let previousNumber = previousNumberOfNumberedList(textView.selectedRange)
                var newNumber = (previousNumber ?? 0) + 1
                
                let previousNumberedIndex = textView.text.previousIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: textView.selectedRange.location) ?? -2
                let previousNewLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: textView.selectedRange.location) ?? -1

                if previousNumberedIndex < previousNewLineIndex {
                    addText("\(newNumber)\(RichTextViewController.numberedListTrailer)", toTextView: textView, atIndex: previousNewLineIndex + 1)
                    newNumber += 1
                }

                var index = textView.selectedRange.location

                while index < textView.text.length {
                    guard let newLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: index), newLineIndex < textView.selectedRange.endLocation else { break }
                    
                    addText("\(newNumber)\(RichTextViewController.numberedListTrailer)", toTextView: textView, atIndex: newLineIndex + 1)
                    newNumber += 1
                    index = newLineIndex + 1
                }
                
            }
        }
    }
    
    /// Returns the range of the previous "numbered list" line, starting at the beginning of the line
    ///
    /// - parameter index: The index to begin searching from.  Search will go before the index
    /// - parameter inString: The string to search in
    ///
    /// - returns: An `NSRange` describing the location of the previous number i.e. `"1. "`
    fileprivate func previousNumberedRangeFromIndex(_ index: Int, inString string: String) -> NSRange? {
        guard let numberedTrailerIndex = string.previousIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: index) else { return nil }
        
        var newLineIndex = string.previousIndexOfSubstring("\n", fromIndex: numberedTrailerIndex) ?? -1
        if newLineIndex >= -1 {
            newLineIndex += 1
        }
        
        return NSRange(location: newLineIndex, length: (numberedTrailerIndex - newLineIndex) + RichTextViewController.numberedListTrailer.length)
    }
    
    /// Returns the range of the next "numbered list" line, starting at the beginning of the line
    ///
    /// - parameter index: The index to begin searching from.  Search will go after the index
    /// - parameter inString: The string to search in
    ///
    /// - returns: An `NSRange` describing the location of the next number i.e. `"1. "`
    fileprivate func nextNumberedRangeFromIndex(_ index: Int, inString string: String) -> NSRange? {
        guard let numberedTrailerIndex = string.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: index) else { return nil }
        
        var newLineIndex = string.previousIndexOfSubstring("\n", fromIndex: numberedTrailerIndex) ?? -1
        if newLineIndex >= -1 {
            newLineIndex += 1
        }
        
        return NSRange(location: newLineIndex, length: (numberedTrailerIndex - newLineIndex) + RichTextViewController.numberedListTrailer.length)
    }
    
    /// Checks a `NSRange` selection to see if it contains a numbered list.
    /// Returns true if selection contains at least 1 numbered list, false otherwise.
    ///
    /// - parameter selection: An `NSRange` to check
    ///
    /// - returns: True if selection contains at least 1 numbered list, false otherwise
    open func selectionContainsNumberedList(_ range: NSRange) -> Bool {
        var containsNumberedList = false
        var selection = NSRange(location: range.location, length: range.length)
        
        if selection.length == 0 {
            if let previousIndex = textView.text.previousIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: selection.location) {
                let newLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: selection.location) ?? 0
                if let comparisonIndex = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: newLineIndex), previousIndex == comparisonIndex {
                    containsNumberedList = true
                }
            }
        } else {
            let previousNumberedListIndex = textView.text.previousIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: selection.location) ?? selection.location
            let previousNewLineIndex = textView.text.previousIndexOfSubstring("\n", fromIndex: selection.location) ?? 0
            
            if previousNewLineIndex < previousNumberedListIndex {
                selection.location = previousNumberedListIndex
                selection.length = selection.length < 2 && (selection.location + 2 < textView.text.length) ? 2 : selection.length
                
                
                let substring = (textView.text as NSString).substring(with: selection)
                
                if substring.contains(RichTextViewController.numberedListTrailer) {
                    containsNumberedList = true
                }
            } else if (textView.text as NSString).substring(with: selection).contains(RichTextViewController.numberedListTrailer) {
                containsNumberedList = true
            }
        }
        
        return containsNumberedList
    }
    
    /// Returns the number of the previous number starting from the location of the selection.
    ///
    /// - parameter selection: The selection to check from
    ///
    /// - returns: Previous number if it exists in the current line or previous line, `nil` otherwise
    fileprivate func previousNumberOfNumberedList(_ selection: NSRange) -> Int? {
        guard let previousNumberTrailIndex = textView.text.previousIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: selection.location) else { return nil }
        
        let indexOfPreviousNumberNewLine = textView.text.nextIndexOfSubstring("\n", fromIndex: previousNumberTrailIndex) ?? textView.text.length
        let indexOfNextNewLine = textView.text.nextIndexOfSubstring("\n", fromIndex: min(indexOfPreviousNumberNewLine + 1, textView.text.length)) ?? textView.text.length
        
        if selection.location <= indexOfNextNewLine {
            // Find the previous new line so we can get the entire number
            let indexOfNewLineBeforePreviousNumberTrailIndex = (textView.text.previousIndexOfSubstring("\n", fromIndex: previousNumberTrailIndex) ?? -1) + 1
            return Int((textView.text as NSString).substring(with: NSRange(location: indexOfNewLineBeforePreviousNumberTrailIndex, length: previousNumberTrailIndex - indexOfNewLineBeforePreviousNumberTrailIndex)))
        }
        
        return nil
    }
    
    /// Appends a number to the text view if we are currently in a list.  Also deletes existing number if there is no text on the line.  This function should be called when the user inserts a new line (presses return)
    ///
    /// - parameter range: The location to insert the number
    ///
    /// - returns: `true` if a number was added, `false` otherwise
    fileprivate func addedListsIfActiveInRange(_ range: NSRange) -> Bool {
        if selectionContainsNumberedList(range) {
            let previousNumber = previousNumberOfNumberedList(range) ?? 0
            let previousNumberString = "\(previousNumber)\(RichTextViewController.numberedListTrailer)"
            let previousRange = NSRange(location: range.location - previousNumberString.length, length: previousNumberString.length)
            var newNumber = previousNumber + 1
            let newNumberString = "\n\(newNumber)\(RichTextViewController.numberedListTrailer)"
            
            if textView.attributedText.attributedSubstring(from: previousRange).string == previousNumberString {
                removeTextFromRange(previousRange, fromTextView: textView)
            } else {
                addText(newNumberString, toTextView: textView, atIndex: range.location)
                
                var index = range.location + newNumberString.length
                
                while index < textView.text.length {
                    let stringToReplace = "\(newNumber)\(RichTextViewController.numberedListTrailer)"
                    index = textView.text.nextIndexOfSubstring(stringToReplace, fromIndex: index) ?? -1
                    guard index >= 0 else { break }
                    
                    newNumber += 1
                    
                    replaceTextInRange(NSRange(location: index, length: stringToReplace.length), withText: "\(newNumber)\(RichTextViewController.numberedListTrailer)", inTextView: textView)
                    index += 1
                }
            }
            
            return true
        } else if selectionContainsBulletedList(range) {
            let previousRange = NSRange(location: range.location - RichTextViewController.bulletedLineStarter.length, length: RichTextViewController.bulletedLineStarter.length)
            let bulletedString = "\n" + RichTextViewController.bulletedLineStarter
            
            if let subString = textView.attributedText?.attributedSubstring(from: previousRange).string, subString == RichTextViewController.bulletedLineStarter {
                textView.textStorage.beginEditing()
                textView.textStorage.replaceCharacters(in: previousRange, with: NSAttributedString(string: "", attributes: textView.typingAttributes))
                textView.textStorage.endEditing()
            } else {
                addText(bulletedString, toTextView: textView, atIndex: range.location)
            }
            textView.selectedRange = NSRange(location: range.location + (bulletedString as NSString).length, length: 0)
            
            return true
        }
        return false
    }
    
    /// Removes a number from a numbered list.  This function should be called when the user is backspacing on a number of a numbered list
    ///
    /// - parameter range: The range from which to remove the number
    ///
    /// - returns: true if a number was removed, false otherwise
    fileprivate func removedListsIfActiveInRange(_ range: NSRange) -> Bool {
        guard textView.selectedRange.location >= 2 else { return false }
        
        let previousNumber = previousNumberOfNumberedList(textView.selectedRange) ?? 0
        let previousNumberString = "\(previousNumber)\(RichTextViewController.numberedListTrailer)"
        var previousNumberRange = NSRange(location: range.location - previousNumberString.length + 1, length: previousNumberString.length)
        let previousBulletRange = NSRange(location: range.location - RichTextViewController.bulletedLineStarter.length + 1, length: RichTextViewController.bulletedLineStarter.length)
        let adjustedRange = NSRange(location: range.location + 1, length: 0)
        
        if selectionContainsNumberedList(adjustedRange) {
            var removed = false
            
            let subString = (textView.text as NSString).substring(with: previousNumberRange)
            
            if subString == previousNumberString {
                if previousNumber > 1 {
                    // Not at the beginning of the list, so collapse the list
                    let space = CharacterSet.whitespacesAndNewlines
                    let text = textView.text as NSString
                    while previousNumberRange.location > 0 {
                        if space.contains(UnicodeScalar(text.character(at: previousNumberRange.location - 1))!) {
                            previousNumberRange.location = previousNumberRange.location - 1
                            previousNumberRange.length = previousNumberRange.length + 1
                        } else {
                            break
                        }
                    }
                }
                
                // Update following numbers in list so there isn't a hole
                var newNumber = previousNumber
                var index = previousNumberRange.location
                
                repeat {
                    let stringToReplace = "\(newNumber + 1)\(RichTextViewController.numberedListTrailer)"
                    index = textView.text.nextIndexOfSubstring(stringToReplace, fromIndex: index) ?? -1
                    guard index >= 0 else { break }
                    
                    replaceTextInRange(NSRange(location: index, length: stringToReplace.length), withText: "\(newNumber)\(RichTextViewController.numberedListTrailer)", inTextView: textView)
                    newNumber += 1
                    index += 1
                } while index < textView.text.length
                
                removeTextFromRange(previousNumberRange, fromTextView: textView, applyDefault: previousNumber == 1)
                removed = true
            }
            return removed
        } else if selectionContainsBulletedList(adjustedRange) {
            var removed = false
            
            let subString = (textView.text as NSString).substring(with: previousBulletRange)
            if subString == RichTextViewController.bulletedLineStarter {
                textView.textStorage.beginEditing()
                textView.textStorage.replaceCharacters(in: previousBulletRange, with: "")
                textView.textStorage.endEditing()
                textView.selectedRange = NSRange(location: previousBulletRange.location, length: 0)
                removed = true
            }
            
            return removed
        }
        
        return false
    }
    
    /// Moves the selection out of a number.  Call this when a selection changes
    fileprivate func moveSelectionIfInRangeOfNumberedList() {
        guard textView.text.length > 3 else { return }
        
        var range = NSRange(location: textView.selectedRange.location, length: textView.selectedRange.length)
        
        func stringAtRange(_ range: NSRange) -> String {
            return (textView.text as NSString).substring(with: range)
        }
        
        if range.length == 0 {
            if range.location <= textView.text.length - 1 && stringAtRange(NSRange(location: range.location, length: 1)) == RichTextViewController.spaceAfterNumberCharacter {
                if previousSelection.location < range.location {
                    range.location += 1
                } else {
                    range.location = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location) ?? 0
                }
            } else if range.location <= textView.text.length - 2 && stringAtRange(NSRange(location: range.location, length: 2)) == RichTextViewController.numberedListTrailer {
                if previousSelection.location < range.location {
                    range.location += 2
                } else {
                    range.location = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location) ?? 0
                }
            } else if range.location > 0 && range.location < textView.text.length - 1 && stringAtRange(NSRange(location: range.location - 1, length: 1)) == "\n", let nextTrailerIndex = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location) {
                let nextLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: range.location) ?? textView.text.length
                if nextTrailerIndex < nextLineIndex {
                    if previousSelection.location < range.location {
                        range.location = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location) ?? textView.text.length
                    } else {
                        range.location -= 1
                    }
                }
            }
        } else {
            if range.location <= textView.text.length - 1 && stringAtRange(NSRange(location: range.location, length: 1)) == RichTextViewController.spaceAfterNumberCharacter {
                if previousSelection.location < range.location {
                    range.location += 1
                    range.length -= 1
                } else {
                    let oldLocation = range.location
                    range.location = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location) ?? 0
                    let lengthChange = oldLocation - range.location
                    range.length += lengthChange
                }
            } else if range.location <= textView.text.length - 2 && stringAtRange(NSRange(location: range.location, length: 2)) == RichTextViewController.numberedListTrailer {
                if previousSelection.location < range.location {
                    range.location += 2
                    range.length -= 2
                } else {
                    let oldLocation = range.location
                    range.location = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location) ?? 0
                    let lengthChange = oldLocation - range.location
                    range.length += lengthChange
                }
            } else if range.location > 0 && range.location < textView.text.length - 1 && stringAtRange(NSRange(location: range.location - 1, length: 1)) == "\n",
                let nextTrailerIndex = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location),
                let nextLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: range.location), nextTrailerIndex < nextLineIndex {
                if previousSelection.location < range.location {
                    let oldLocation = range.location
                    range.location = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location) ?? textView.text.length - 2
                    range.location += 2
                    let lengthChange = range.location - oldLocation
                    range.length -= lengthChange
                } else {
                    range.location -= 1
                    range.length += 1
                }
            }
            
            if range.location + range.length <= textView.text.length - 1 && stringAtRange(NSRange(location: range.location + range.length, length: 1)) == RichTextViewController.spaceAfterNumberCharacter {
                if previousSelection.length < range.length {
                    range.length += 1
                } else {
                    var newLength = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location + range.length) ?? range.length + 1
                    newLength -= newLength != range.length + 1 ? range.location : 0
                    range.length = newLength
                }
            } else if range.location + range.length <= textView.text.length - 2 && stringAtRange(NSRange(location: range.location + range.length, length: 2)) == RichTextViewController.numberedListTrailer {
                if previousSelection.length < range.length {
                    range.length += 2
                } else {
                    var newLength = textView.text.previousIndexOfSubstring("\n", fromIndex: range.location + range.length) ?? range.length + 2
                    newLength -= newLength != range.length + 2 ? range.location : 0
                    range.length = newLength
                }
            } else if range.location + range.length < textView.text.length - 1 && stringAtRange(NSRange(location: (range.location + range.length) - 1, length: 1)) == "\n",
                let nextTrailerIndex = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location + range.length) {
                let nextLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: range.location + range.length) ?? textView.text.length - 1
                if nextTrailerIndex < nextLineIndex {
                    if previousSelection.length < range.length {
                        var newLength = textView.text.nextIndexOfSubstring(RichTextViewController.numberedListTrailer, fromIndex: range.location + range.length) ?? range.length - 1
                        newLength = newLength != range.length - 1 ? (newLength - range.location) + 2 : 0
                        range.length = newLength
                    } else {
                        range.length -= 1
                    }
                }
            }
        }
        
        if range.location != textView.selectedRange.location || range.length != textView.selectedRange.length {
            textView.selectedRange = range
        }
    }
    
    // MARK: Font Adjustments
    
    fileprivate func applyFontAttribute(_ font: UIFont) {
        guard let attributedString = textView.attributedText else { return }
        
        let attributedText = NSMutableAttributedString(attributedString: attributedString)
        
        attributedText.beginEditing()
        attributedText.enumerateAttributes(in: textView.selectedRange, options: []) { _, range, _ in
            attributedText.addAttribute(NSAttributedString.Key.font, value: font, range: range)
        }
        attributedText.endEditing()
        
        textView.attributedText = attributedText
    }
    
    fileprivate func removeFormattingFromListLeadsInRange(_ range: NSRange) {
        guard let regularFont = regularFont else { return }
        guard range.length > 0, let listHeadRegex = try? NSRegularExpression(pattern: "^(([0-9]+\\.\\u00A0)|(\\u2022\\u00A0)).*$", options: .anchorsMatchLines) else {
            print("Failed to remove formatting")
            return
        }
        
        listHeadRegex.matches(in: textView.text, options: [], range: range).forEach { match in
            let matchedRange = match.range(at: 1)
            self.textView.textStorage.beginEditing()
            self.textView.textStorage.setAttributes([NSAttributedString.Key.font: regularFont], range: matchedRange)
            self.textView.textStorage.endEditing()
        }
    }
    
    // MARK: Bold Functions
    
    open func selectionContainsBold(_ range: NSRange) -> Bool {
        guard !disableBold else { return false }
        
        var font = range.length == 0 ? textView.typingAttributes[NSAttributedString.Key.font] as? UIFont : nil
        textView.attributedText.enumerateAttributes(in: range, options: []) { dictionary, _, _ in
            font = font ?? dictionary[NSAttributedString.Key.font] as? UIFont
        }
        
        return font == boldFont || font == boldItalicFont
    }
    
    open func toggleBold() {
        guard let regularFont = regularFont, let boldFont = boldFont, let italicFont = italicFont, let boldItalicFont = boldItalicFont else { return }
        
        let rangeLongerThanZero = textView.selectedRange.length > 0
        let isItalic = selectionContainsItalic(textView.selectedRange)
        let isBold = selectionContainsBold(textView.selectedRange)
        let fontToApply = !isBold ? (isItalic ? boldItalicFont : boldFont) : (isItalic ? italicFont : regularFont)
        let rangeToApplyFontTo = textView.selectedRange
        if rangeLongerThanZero {
            applyFontAttribute(fontToApply)
        } else {
            textView.typingAttributes[NSAttributedString.Key.font] = fontToApply
        }
        
        disableBold = isBold
        removeFormattingFromListLeadsInRange(rangeToApplyFontTo)
    }
    
    // MARK: Italic Functions
    
    open func selectionContainsItalic(_ range: NSRange) -> Bool {
        guard !disableItalic else { return false }
        
        var font = range.length == 0 ? textView.typingAttributes[NSAttributedString.Key.font] as? UIFont : nil
        textView.attributedText.enumerateAttributes(in: range, options: []) { dictionary, _, _ in
            font = font ?? dictionary[NSAttributedString.Key.font] as? UIFont
        }
        
        return font == italicFont || font == boldItalicFont
    }
    
    open func toggleItalic() {
        guard let regularFont = regularFont, let boldFont = boldFont, let italicFont = italicFont, let boldItalicFont = boldItalicFont else { return }
        
        let rangeLongerThanZero = textView.selectedRange.length > 0
        let isItalic = selectionContainsItalic(textView.selectedRange)
        let isBold = selectionContainsBold(textView.selectedRange)
        let fontToApply = !isItalic ? (isBold ? boldItalicFont : italicFont) : (isBold ? boldFont : regularFont)
        let rangeToApplyFontTo = textView.selectedRange
        if rangeLongerThanZero {
            applyFontAttribute(fontToApply)
        } else {
            textView.typingAttributes[NSAttributedString.Key.font] = fontToApply
        }
        
        disableItalic = isItalic
        removeFormattingFromListLeadsInRange(rangeToApplyFontTo)
    }
    
    // MARK: Bulleted Lists
    
    open func selectionContainsBulletedList(_ selection: NSRange) -> Bool {
        var containsBulletedList = false
        
        if let previousIndex = textView.text.previousIndexOfSubstring(RichTextViewController.bulletedLineStarter, fromIndex: selection.location) {
            let newLineIndex = (textView.text.previousIndexOfSubstring("\n", fromIndex: selection.location) ?? -1) + 1
            containsBulletedList = newLineIndex == previousIndex
        }
        
        if selection.length > 0 && !containsBulletedList {
            containsBulletedList = (textView.text as NSString).substring(with: selection).contains(RichTextViewController.bulletedLineStarter)
        }
        
        return containsBulletedList
    }
    
    fileprivate func moveSelectionIfInRangeOfBulletedList() {
        guard textView.text.length > 1 && textView.selectedRange.location < textView.text.length else { return }
        
        var range = NSRange(location: textView.selectedRange.location, length: textView.selectedRange.length)
        if range.length == 0 && range.location > 0 {
            range.length = 2
            while range.length + range.location > textView.text.length {
                range.location -= 1
            }
        }
        var loops = 0
        var testString = (textView.text as NSString).substring(with: range)
        while loops < 2 {
            if testString == RichTextViewController.bulletedLineStarter {
                range.location += 2
                range.length = 0
                textView.selectedRange = range
                break
            }
            
            if range.location > 0 {
                range.location -= 1
            } else {
                break
            }
            testString = (textView.text as NSString).substring(with: range)
            loops += 1
        }
    }
    
    open func toggleBulletedList() {
        if selectionContainsNumberedList(textView.selectedRange) {
            toggleNumberedList()
        }
        
        if textView.selectedRange.length == 0 {
            if selectionContainsBulletedList(textView.selectedRange) {
                if let bulletIndex = textView.text.previousIndexOfSubstring(RichTextViewController.bulletedLineStarter, fromIndex: textView.selectedRange.location) {
                    removeTextFromRange(NSRange(location: bulletIndex, length: RichTextViewController.bulletedLineStarter.length), fromTextView: textView)
                }
            } else {
                let newLineIndex = (textView.text.previousIndexOfSubstring("\n", fromIndex: textView.selectedRange.location) ?? -1) + 1
                addText(RichTextViewController.bulletedLineStarter, toTextView: textView, atIndex: newLineIndex)
            }
        } else {
            var bulletsInSelection = false
            
            if selectionContainsBulletedList(NSRange(location: textView.selectedRange.location, length: 0)), let bulletIndex = textView.text.previousIndexOfSubstring(RichTextViewController.bulletedLineStarter, fromIndex: textView.selectedRange.location) {
                bulletsInSelection = true
                removeTextFromRange(NSRange(location: bulletIndex, length: RichTextViewController.bulletedLineStarter.length), fromTextView: textView)
            }
            
            if selectionContainsBulletedList(textView.selectedRange) {
                bulletsInSelection = true
                var index = textView.selectedRange.location
                while index < textView.text.length {
                    guard let nextBulletIndex = textView.text.nextIndexOfSubstring(RichTextViewController.bulletedLineStarter, fromIndex: index) else { break }
                    
                    removeTextFromRange(NSRange(location: nextBulletIndex, length: RichTextViewController.bulletedLineStarter.length), fromTextView: textView)
                    index = nextBulletIndex
                }
            }
            
            if !bulletsInSelection {
                let newLineIndex = (textView.text.previousIndexOfSubstring("\n", fromIndex: textView.selectedRange.location) ?? -1) + 1
                addText(RichTextViewController.bulletedLineStarter, toTextView: textView, atIndex: newLineIndex)
                
                var index = textView.selectedRange.location
                while index < textView.text.length {
                    guard let nextLineIndex = textView.text.nextIndexOfSubstring("\n", fromIndex: index) else { break }
                    
                    addText(RichTextViewController.bulletedLineStarter, toTextView: textView, atIndex: nextLineIndex + 1)
                    index = nextLineIndex + 1
                }
            }
        }
    }
    
}

extension RichTextViewController: UITextViewDelegate {
    
    open func textViewDidChangeSelection(_ textView: UITextView) {
        disableBold = false
        disableItalic = false
        
        moveSelectionIfInRangeOfNumberedList()
        moveSelectionIfInRangeOfBulletedList()
        previousSelection = textView.selectedRange
    }
    
    open func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        var changed = false

        previousTypingAttributes = textView.typingAttributes

        switch text {
        case "\n":
            changed = addedListsIfActiveInRange(range)
        case "":
            changed = removedListsIfActiveInRange(range)
        default:
            break
        }
        
        return !changed
    }
    
    @objc func textChanged(_ notification: Notification) {
        guard notification.object as? UITextView == textView else { return }

        if let typingAttributes = previousTypingAttributes { textView.typingAttributes = typingAttributes }

        if textView.selectedRange.endLocation == textView.text.length {
            textView.typingAttributes[NSAttributedString.Key.paragraphStyle] = defaultParagraphStyle
        }
    }
    
}
