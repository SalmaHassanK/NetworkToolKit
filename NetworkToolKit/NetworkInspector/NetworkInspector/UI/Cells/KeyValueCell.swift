//
//  KeyValueCell.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 24/03/2026.
//
// Horizontal key–value cell used for HTTP headers (in ``AttemptDetailVC``)
// and overview rows (in ``ChainDetailVC``).
//
// The key label hugs its content on the left while the value label fills
// the remaining width, right-aligned, with multi-line wrapping.

import UIKit

/// Two-column cell: bold key on the left, monospaced value on the right.
///
/// - ``configure(key:value:valueIsEmpty:)`` — for header rows (mono value font).
/// - ``configureOverview(label:value:)`` — for overview rows (regular value font, secondary colour).
final class KeyValueCell: UITableViewCell {
    static let reuseID = "KeyValueCell"

    let keyLabel   = UILabel()
    let valueLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        keyLabel.font      = .systemFont(ofSize: 13, weight: .semibold)
        keyLabel.textColor = .compatSecondary
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font          = .monoFont(ofSize: 12)
        valueLabel.textColor     = .compatLabel
        valueLabel.numberOfLines = 0
        valueLabel.textAlignment = .right

        let stack = UIStackView(arrangedSubviews: [keyLabel, valueLabel])
        stack.axis = .horizontal; stack.spacing = 12; stack.alignment = .center; stack.distribution = .fill

        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(key: String, value: String, valueIsEmpty: Bool = false) {
        keyLabel.text        = key
        valueLabel.text      = value
        valueLabel.textColor = valueIsEmpty ? .compatTertiary : .compatLabel
        valueLabel.font      = valueIsEmpty ? .systemFont(ofSize: 12) : .monoFont(ofSize: 12)
    }

    func configureOverview(label: String, value: String) {
        keyLabel.text        = label
        valueLabel.text      = value
        valueLabel.textColor = .compatSecondary
        valueLabel.font      = .systemFont(ofSize: 13)
    }
}
