//
//  DevTool+Styles.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// iOS 12-safe colour and font helpers used across the logger UI.
//
// On iOS 13+ these resolve to the standard semantic system colours / fonts.
// On iOS 12 they fall back to fixed values that approximate the same look.

import UIKit

// MARK: - Colour Compatibility Helpers

extension UIColor {
    static var compatSecondary: UIColor {
        if #available(iOS 13, *) { return .secondaryLabel }
        return UIColor(white: 0.45, alpha: 1)
    }
    static var compatTertiary: UIColor {
        if #available(iOS 13, *) { return .tertiaryLabel }
        return UIColor(white: 0.65, alpha: 1)
    }
    static var compatLabel: UIColor {
        if #available(iOS 13, *) { return .label }
        return .black
    }
    static var compatGroupedBg: UIColor {
        if #available(iOS 13, *) { return .systemGroupedBackground }
        return UIColor(white: 0.95, alpha: 1)
    }
    static var compatSecondaryGroupedBg: UIColor {
        if #available(iOS 13, *) { return .secondarySystemGroupedBackground }
        return .white
    }
    static var compatSeparator: UIColor {
        if #available(iOS 13, *) { return .separator }
        return UIColor(white: 0.78, alpha: 1)
    }
    static var pushPurple: UIColor {
        UIColor(red: 0.49, green: 0.13, blue: 0.74, alpha: 1)
    }
}

// MARK: - Monospaced Font Helper

extension UIFont {
    /// Returns a monospaced system font on iOS 13+, or falls back to Menlo / Courier on iOS 12.
    static func monoFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if #available(iOS 13, *) { return .monospacedSystemFont(ofSize: size, weight: weight) }
        let name = weight == .regular ? "Menlo-Regular" : "Menlo-Bold"
        return UIFont(name: name, size: size)
        ?? UIFont(name: "Courier", size: size)
        ?? .systemFont(ofSize: size)
    }
}
