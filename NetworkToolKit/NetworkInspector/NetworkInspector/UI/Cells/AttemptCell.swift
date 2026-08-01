//
//  AttemptCell.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// Table-view cell representing one ``APIAttempt`` in ``ChainDetailVC``.
//
// ## Layout variants
// - **HTTP request**: Blue (primary) or orange (fallback) numbered badge,
//   attempt label, URL, HTTP status pill, duration.
// - **External completion**: Purple accent bar on the left edge, bell emoji
//   badge, source title with purple tint.

import UIKit

/// Displays a single ``APIAttempt`` row with type-specific styling for HTTP vs
/// external completions.
final class AttemptCell: UITableViewCell {
    static let reuseID = "AttemptCell"

    private let indexBadge    = UILabel()
    private let titleLabel    = UILabel()
    private let urlLabel      = UILabel()
    private let outcomeBadge  = PillLabel()
    private let durationLabel = UILabel()

    // Left accent border — shown for push rows, hidden for HTTP
    private let accentBar = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        indexBadge.font            = .systemFont(ofSize: 10, weight: .bold)
        indexBadge.textAlignment   = .center
        indexBadge.layer.cornerRadius  = 12
        indexBadge.layer.masksToBounds = true
        indexBadge.widthAnchor.constraint(equalToConstant: 24).isActive  = true
        indexBadge.heightAnchor.constraint(equalToConstant: 24).isActive = true

        titleLabel.font    = .systemFont(ofSize: 13, weight: .medium)
        urlLabel.font      = .monoFont(ofSize: 11)
        urlLabel.textColor = .compatSecondary
        urlLabel.lineBreakMode = .byTruncatingMiddle
        durationLabel.font      = .systemFont(ofSize: 11)
        durationLabel.textColor = .compatTertiary
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), durationLabel])
        topRow.axis = .horizontal; topRow.spacing = 6

        let botRow = UIStackView(arrangedSubviews: [urlLabel, outcomeBadge])
        botRow.axis = .horizontal; botRow.spacing = 6; botRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [topRow, botRow])
        textStack.axis = .vertical; textStack.spacing = 3

        let root = UIStackView(arrangedSubviews: [indexBadge, textStack])
        root.axis = .horizontal; root.spacing = 10; root.alignment = .center

        contentView.addSubview(accentBar)
        contentView.addSubview(root)

        accentBar.translatesAutoresizingMaskIntoConstraints = false
        root.translatesAutoresizingMaskIntoConstraints      = false

        NSLayoutConstraint.activate([
            // Accent bar — 3pt left edge, hidden by default
            accentBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            // Content
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with attempt: AttemptDisplayable) {
        durationLabel.text = attempt.durationString

        if attempt.isExternalCompletion {
            applyPush(attempt)
        } else {
            applyHTTP(attempt)
        }
    }

    private func applyHTTP(_ attempt: AttemptDisplayable) {
        accentBar.isHidden       = true
        titleLabel.textColor     = .compatLabel
        titleLabel.text          = attempt.label
        urlLabel.text            = attempt.requestURL
        urlLabel.textColor       = .compatSecondary

        if attempt.index == 0 {
            indexBadge.text            = "1"
            indexBadge.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
            indexBadge.textColor       = .systemBlue
        } else {
            indexBadge.text            = "\(attempt.index + 1)"
            indexBadge.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
            indexBadge.textColor       = .systemOrange
        }

        // Show HTTP code + business status together
        let httpStr = attempt.httpStatusCode.map { "HTTP \($0)" } ?? ""
        outcomeBadge.setText(httpStr, style: .neutral)
    }

    private func applyPush(_ attempt: AttemptDisplayable) {
        // Purple accent bar distinguishes push rows from HTTP rows visually
        accentBar.isHidden       = false
        accentBar.backgroundColor = .pushPurple

        indexBadge.text            = "🔔"
        indexBadge.backgroundColor = UIColor.pushPurple.withAlphaComponent(0.15)
        indexBadge.textColor       = .pushPurple

        titleLabel.text      = attempt.label
        titleLabel.textColor = .pushPurple

        urlLabel.text      = attempt.requestURL
        urlLabel.textColor = .compatSecondary
    }
}
