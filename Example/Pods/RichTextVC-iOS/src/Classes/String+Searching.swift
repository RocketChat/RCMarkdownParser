//
//  String+Searching.swift
//  NumberedLists
//
//  Created by Rhett Rogers on 3/7/16.
//  Copyright © 2016 LyokoTech. All rights reserved.
//

import Foundation

extension NSString {

    /// Gets the previous index of a substring contained within the `String`
    ///
    /// - parameter searchString: The string to search for
    /// - parameter fromIndex: The index to start the search from.  The search will move backwards from this index.
    ///
    /// - returns: Index of the searchString passed in. Nil if `fromIndex` is invalid, or if string is not found.
    func previousIndexOfSubstring(_ searchString: String, fromIndex: Int) -> Int? {
        if fromIndex < 0 {
            return nil
        }

        let substring = self.substring(to: fromIndex) as NSString
        let range = substring.range(of: searchString as String, options: .backwards)
        return range.location == NSNotFound ? nil : range.location
    }

    /// Gets the next index of a substring contained within the `String`
    ///
    /// - parameter searchString: The string to search for
    /// - parameter fromIndex: The index to start the search from.  The search will move forwards from this index.
    ///
    /// - returns: Index of the searchString passed in. Nil if `fromIndex` is invalid, or if string is not found.
    func nextIndexOfSubstring(_ searchString: String, fromIndex: Int) -> Int? {
        if fromIndex < 0 {
            return nil
        }
        
        let substring = self.substring(from: fromIndex) as NSString
        let range = substring.range(of: searchString as String)
        return range.location == NSNotFound ? nil : range.location + fromIndex
    }

}

extension String {
    
    var length: Int {
        return (self as NSString).length
    }
    
}
