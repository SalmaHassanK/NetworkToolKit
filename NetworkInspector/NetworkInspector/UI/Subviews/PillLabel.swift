//
//  PillLabel.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 24/03/2026.
//
// A small coloured badge label used throughout the logger UI to display
// status indicators (e.g. "SUCCESS", "2 fallbacks", "1 push").

import UIKit

/// Compact rounded-corner label with tinted background.
///
/// Call ``setText(_:style:)`` to update both the text and colour scheme.
/// The pill automatically hugs its content and resists compression so it
/// never clips inside horizontal stack views.
final class PillLabel: UILabel {
    /// Visual style that determines background tint and text colour.
    enum Style { case success, warning, danger, neutral, push }

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 10, weight: .semibold)
        layer.cornerRadius = 4; layer.masksToBounds = true
        textAlignment = .center
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String, style: Style) {
        self.text = "  \(text)  "
        switch style {
        case .success: backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15);  textColor = .systemGreen
        case .warning: backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15); textColor = .systemOrange
        case .danger:  backgroundColor = UIColor.systemRed.withAlphaComponent(0.15);    textColor = .systemRed
        case .neutral: backgroundColor = UIColor.systemGray.withAlphaComponent(0.15);   textColor = .systemGray
        case .push:    backgroundColor = UIColor.pushPurple.withAlphaComponent(0.15);   textColor = .pushPurple
        }
    }
}
