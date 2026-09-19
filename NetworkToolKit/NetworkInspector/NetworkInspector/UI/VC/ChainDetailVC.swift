//
//  ChainDetailVC.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 24/03/2026.
//
// Detail screen for a single ``APIRequestChain``.
//
// ## Sections
// 1. **Overview** — transport-level rows (tag, total, HTTP / push / fallback
//    counts).
// 2. **Business insights** — host-supplied rows from the active
//    ``ChainBusinessInsights`` (status codes, backend request id, error
//    details). Omitted when the host supplies no rows.
// 3. **Attempt chain** — one row per ``APIAttempt`` (primary, fallback, push).
//    Tapping a row pushes ``AttemptDetailVC``.
//
// ## Live updates
// The controller observes both `chain.attempts` and `chain.isResolved` via
// ReactiveSwift signals so the table refreshes automatically when new attempts
// arrive or the chain resolves.
//
// ## Thread safety
// A local `attemptsSnapshot` array is captured on the main thread before each
// reload so the data-source methods never read the reactive property mid-mutation.

import UIKit
import ReactiveSwift

/// Factory that returns an inset-grouped table on iOS 13+ or a plain grouped table on iOS 12.
func makeTableView() -> UITableView {
    if #available(iOS 13, *) { return UITableView(frame: .zero, style: .insetGrouped) }
    return UITableView(frame: .zero, style: .grouped)
}

/// Shows the overview and attempt timeline for a single ``APIRequestChain``.
///
/// Pushed from ``APILogsPanelVC`` when the user taps a chain row.
final class ChainDetailVC: UIViewController {

    private let chain: APIRequestChain
    private let tracker: NetworkInspectorReadable
    private let uiConfiguration: NetworkInspectorUIConfiguration
    private var insights: ChainBusinessInsights? { uiConfiguration.insights }
    private var shareBarItem: UIBarButtonItem?
    private let disposables = CompositeDisposable()

    /// Snapshot of attempts captured on the main thread before each reload.
    /// All table-view data-source reads must use this instead of `chain.attempts.value`
    /// to avoid EXC_BAD_ACCESS from concurrent mutation.
    private var attemptsSnapshot: [APIAttempt] = []

    private lazy var tableView: UITableView = {
        let tv = makeTableView()
        tv.register(KeyValueCell.self,  forCellReuseIdentifier: KeyValueCell.reuseID)
        tv.register(AttemptCell.self,   forCellReuseIdentifier: AttemptCell.reuseID)
        tv.dataSource         = self
        tv.delegate           = self
        tv.rowHeight          = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        return tv
    }()

    init(
        chain: APIRequestChain,
        tracker: NetworkInspectorReadable = InMemoryNetworkRecorder.shared,
        uiConfiguration: NetworkInspectorUIConfiguration = .init()
    ) {
        self.chain = chain
        self.tracker = tracker
        self.uiConfiguration = uiConfiguration
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { disposables.dispose() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = chain.tag

        let shareItem: UIBarButtonItem
        if #available(iOS 13, *) {
            shareItem = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain, target: self, action: #selector(shareChain)
            )
        } else {
            shareItem = UIBarButtonItem(
                title: "Share", style: .plain, target: self, action: #selector(shareChain)
            )
        }
        self.shareBarItem = shareItem
        navigationItem.rightBarButtonItem = shareItem

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        disposables += chain.attempts.signal
            .observe(on: UIScheduler())
            .observeValues { [weak self] _ in self?.reloadTable() }

        disposables += chain.isResolved.signal
            .observe(on: UIScheduler())
            .observeValues { [weak self] _ in self?.reloadTable() }

        reloadTable()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else { return }

        let text: String
        switch section(at: indexPath.section) {
        case .overview:
            let (label, value) = overviewRows[indexPath.row]
            text = "\(label): \(value)"
        case .businessInsights:
            let (label, value) = businessRows[indexPath.row]
            text = "\(label): \(value)"
        case .attempts:
            return
        }

        UIPasteboard.general.string = text
        showCopiedToast()
    }

    private func showCopiedToast() {
        let toast = UILabel()
        toast.text = "Copied"
        toast.font = .systemFont(ofSize: 13, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            toast.widthAnchor.constraint(equalToConstant: 100),
            toast.heightAnchor.constraint(equalToConstant: 32),
        ])
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0.8, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    private func reloadTable() {
        attemptsSnapshot = chain.attempts.value
        tableView.reloadData()
    }

    @objc private func shareChain() {
        let coordinator = ExportShareCoordinator(
            formats: uiConfiguration.exportFormats,
            barButton: shareBarItem,
            plainText: { [chain, tracker, uiConfiguration] in
                let content = APILogExporter.exportChain(chain, insights: uiConfiguration.insights)
                return (
                    name: APILogExporter.chainFileName(tag: chain.tag, tracker: tracker),
                    content: content
                )
            },
            markdown: { [chain, tracker, uiConfiguration] in
                let content = APILogExporter.exportAllMarkdownCollapsible(chains: [chain], insights: uiConfiguration.insights)
                return (
                    name: APILogExporter.chainFileName(tag: chain.tag, tracker: tracker, ext: "md"),
                    content: content
                )
            },
            bruno: { [chain] in APILogExporter.exportBrunoCollection(chains: [chain]) }
        )
        coordinator.present(from: self)
    }

    private enum Section { case overview, businessInsights, attempts }

    /// Sections rendered in the table. `businessInsights` is included only
    /// when the host-supplied insights provider returned rows for this chain.
    private var sections: [Section] {
        businessRows.isEmpty ? [.overview, .attempts] : [.overview, .businessInsights, .attempts]
    }

    private func section(at index: Int) -> Section { sections[index] }

    /// Transport-level rows owned by the inspector. The internal correlation
    /// id is intentionally omitted — it's the inspector's grouping key, not
    /// the backend request id (which the insights provider surfaces when
    /// available).
    private var overviewRows: [(String, String)] {
        [
            ("Tag",         chain.tag),
            ("Total",       chain.totalDurationString),
            ("HTTP",        "\(chain.httpCount)"),
            ("External completions", "\(chain.externalCompletionCount)"),
            ("Fallbacks",   "\(chain.fallbackCount)"),
        ]
    }

    /// Host-supplied rows (backend ids, business status, error details).
    private var businessRows: [(String, String)] {
        insights?.overviewRows(for: chain) ?? []
    }
}

extension ChainDetailVC: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tv: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch self.section(at: section) {
        case .overview:         return "Overview"
        case .businessInsights: return "Business insights"
        case .attempts:         return "Attempt chain"
        }
    }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.section(at: section) {
        case .overview:         return overviewRows.count
        case .businessInsights: return businessRows.count
        case .attempts:         return attemptsSnapshot.count
        }
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch section(at: indexPath.section) {
        case .overview:
            let cell = tv.dequeueReusableCell(withIdentifier: KeyValueCell.reuseID, for: indexPath) as! KeyValueCell
            let (label, value) = overviewRows[indexPath.row]
            cell.configureOverview(label: label, value: value)
            return cell

        case .businessInsights:
            let cell = tv.dequeueReusableCell(withIdentifier: KeyValueCell.reuseID, for: indexPath) as! KeyValueCell
            let (label, value) = businessRows[indexPath.row]
            cell.configureOverview(label: label, value: value)
            return cell

        case .attempts:
            // Single cell type handles both HTTP and push — switches internally on attempt.type
            let cell = tv.dequeueReusableCell(withIdentifier: AttemptCell.reuseID, for: indexPath) as! AttemptCell
            cell.configure(with: attemptsSnapshot[indexPath.row])
            return cell
        }
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        guard case .attempts = section(at: indexPath.section) else { return }
        let attempt = attemptsSnapshot[indexPath.row]
        navigationController?.pushViewController(AttemptDetailVC(attempt: attempt), animated: true)
    }

    func tableView(_ tv: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if case .attempts = section(at: indexPath.section) { return true }
        return false
    }
}
