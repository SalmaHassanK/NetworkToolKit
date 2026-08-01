//
//  MonoCell.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// A simple table-view cell that renders text in a monospaced font.
// Used in ``AttemptDetailVC`` to display URLs, request bodies, and response bodies.

import UIKit

/// Full-width monospaced-text cell with unlimited line wrapping.
///
/// Supports both plain text (``configure(text:)``) and attributed text
/// (``configure(attributed:)``).
final class MonoCell: UITableViewCell {
    static let reuseID = "MonoCell"
    private let label  = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle  = .none
        label.font      = .monoFont(ofSize: 11)
        label.numberOfLines = 0
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String) {
        label.attributedText = nil
        label.text      = text
        label.textColor = text == "Empty" ? .compatTertiary : .compatLabel
    }

    func configure(attributed: NSAttributedString) {
        label.text = nil
        label.attributedText = attributed
    }

    /// Returns the plain-text content for clipboard copy.
    var copyableText: String {
        label.attributedText?.string ?? label.text ?? ""
    }
}
