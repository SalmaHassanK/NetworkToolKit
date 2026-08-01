//
//  ChainCell.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// Table-view cell representing one ``APIRequestChain`` in ``APILogsPanelVC``.
//
// ## Layout
// ```
// [outcome emoji]  tag                          duration
//                  [HTTP badge] [status] [external] [fallback]
//                  host URL (truncated middle)
// ```
//
// ## Reactive updates
// Each cell subscribes to `chain.attempts` publisher so it refreshes live
// as new attempts are added or resolved. The subscription is disposed
// in `prepareForReuse()` to prevent stale updates after cell recycling.

import UIKit
import Combine

/// Displays a single ``APIRequestChain`` row with tag, duration, URL, and status badges.
final class ChainCell: UITableViewCell {
    static let reuseID = "ChainCell"

    private var cancellable: AnyCancellable?
    private var insights: ChainBusinessInsights?

    /// Host `badges(for:)` implementations typically JSON-parse response
    /// bodies, so the result is cached and recomputed only when the chain's
    /// visible state changes — not on every scroll or signal tick.
    private struct BadgeCacheKey: Equatable {
        let chainID: String
        let attemptCount: Int
        let lastAttemptHasResponse: Bool
        let isResolved: Bool
    }
    private var badgeCache: (key: BadgeCacheKey, badges: [StatusBadge])?

    private let tagLabel      = UILabel()
    private let durationLabel = UILabel()
    private let hostLabel     = UILabel()
    private let fallbackBadge      = PillLabel()
    private let hostBadge          = PillLabel()   // host-supplied (e.g. business status)
    private let chainStatusBadge   = PillLabel()   // transport-level outcome
    private let externalBadge      = PillLabel()   // shows external completion count when > 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        tagLabel.font     = .monoFont(ofSize: 13, weight: .bold)
        tagLabel.textColor = .compatLabel
        tagLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        durationLabel.font      = .systemFont(ofSize: 11)
        durationLabel.textColor = .compatTertiary
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        hostLabel.font      = .monoFont(ofSize: 11)
        hostLabel.textColor = .compatSecondary
        hostLabel.lineBreakMode = .byTruncatingMiddle

        let topRow = UIStackView(arrangedSubviews: [tagLabel, UIView(), durationLabel])
        topRow.axis = .horizontal; topRow.spacing = 6

        let badgeRow = UIStackView(arrangedSubviews: [chainStatusBadge, hostBadge, UIView(), externalBadge, fallbackBadge])
        badgeRow.axis = .horizontal; badgeRow.spacing = 6; badgeRow.alignment = .leading

        let textStack = UIStackView(arrangedSubviews: [topRow, badgeRow, hostLabel])
        textStack.axis = .vertical; textStack.spacing = 4

        let root = UIStackView(arrangedSubviews: [textStack])
        root.axis = .horizontal; root.spacing = 12; root.alignment = .center

        contentView.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancellable = nil
        insights = nil
        badgeCache = nil
    }

    func configure(with chain: APIRequestChain, insights: ChainBusinessInsights?) {
        self.insights = insights
        cancellable = chain.attempts
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak chain] _ in
                guard let self, let chain else { return }
                self.apply(chain)
            }
        apply(chain)
    }

    private func apply(_ chain: APIRequestChain) {
        tagLabel.text      = chain.tag
        durationLabel.text = chain.totalDurationString
        hostLabel.text     = chain.url.absoluteString

        if chain.fallbackCount > 0 {
            fallbackBadge.isHidden = false
            fallbackBadge.setText(
                "\(chain.fallbackCount) fallback\(chain.fallbackCount > 1 ? "s" : "")", style: .warning
            )
        } else {
            fallbackBadge.isHidden = true
        }

        // External completion badge — purple, only shown when follow-up
        // synthetic completions exist.
        let externalCompletionCount = chain.externalCompletionCount
        if externalCompletionCount > 0 {
            externalBadge.isHidden = false
            externalBadge.setText(
                "\(externalCompletionCount) external",
                style: .push
            )
        } else {
            externalBadge.isHidden = true
        }

        // Host-supplied badges; fall back to a single transport-level outcome
        // when insights aren't wired (or returned nothing). Cell currently
        // renders up to two badges — extra entries are dropped.
        let hostBadges = cachedBadges(for: chain)
        let badges = hostBadges.isEmpty ? [chain.finalOutcome.defaultStatusBadge] : hostBadges
        apply(badge: badges.first, to: chainStatusBadge)
        apply(badge: badges.dropFirst().first, to: hostBadge)
    }

    private func cachedBadges(for chain: APIRequestChain) -> [StatusBadge] {
        let key = BadgeCacheKey(
            chainID: chain.id,
            attemptCount: chain.attempts.value.count,
            lastAttemptHasResponse: chain.lastAttempt?.response != nil,
            isResolved: chain.isResolved.value
        )
        if let cache = badgeCache, cache.key == key { return cache.badges }
        let badges = insights?.badges(for: chain) ?? []
        badgeCache = (key, badges)
        return badges
    }

    private func apply(badge: StatusBadge?, to label: PillLabel) {
        if let badge {
            label.isHidden = false
            label.setText(badge.text, style: badge.severity.pillStyle)
        } else {
            label.isHidden = true
        }
    }
}
