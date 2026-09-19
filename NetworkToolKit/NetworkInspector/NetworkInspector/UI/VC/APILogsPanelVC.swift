//
//  APILogsPanelVC.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// Root view controller of the network logger panel.
//
// ## Navigation hierarchy
// ```
// APILogsPanelVC  (list of chains)
//   → ChainDetailVC  (overview + attempt list for one chain)
//       → AttemptDetailVC  (request/response detail for one attempt)
// ```
//
// ## Features
// - Real-time updates via ReactiveSwift observation on injected tracker chains.
// - Search bar to filter chains by analytics tag.
// - "Clear" button with confirmation to wipe all tracked data.
// - "Share" button that exports the chains via `UIActivityViewController`.
//   When more than one ``ExportFormat`` is enabled in
//   ``NetworkInspectorUIConfiguration/exportFormats``, the action sheet picker
//   is shown first; otherwise the share dialog opens directly.

import UIKit
import ReactiveSwift

/// The main list screen showing every tracked ``APIRequestChain``.
///
/// Present this inside a `UINavigationController` (modally or pushed) to give
/// the user access to the full network logger panel.
public final class APILogsPanelVC: UIViewController {

    private let tracker: NetworkInspectorReadable
    private let uiConfiguration: NetworkInspectorUIConfiguration
    private var chains:   [APIRequestChain] = []
    private var filtered: [APIRequestChain] = []
    private let disposables = CompositeDisposable()

    init(
        tracker: NetworkInspectorReadable = InMemoryNetworkRecorder.shared,
        uiConfiguration: NetworkInspectorUIConfiguration = .init()
    ) {
        self.tracker = tracker
        self.uiConfiguration = uiConfiguration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.register(ChainCell.self, forCellReuseIdentifier: ChainCell.reuseID)
        tv.dataSource         = self
        tv.delegate           = self
        tv.rowHeight          = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
        tv.separatorInset     = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        return tv
    }()

    private lazy var searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder    = "Filter by tag"
        sb.delegate       = self
        sb.searchBarStyle = .minimal
        return sb
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No requests yet"; l.textAlignment = .center
        l.font = .systemFont(ofSize: 15); l.textColor = .compatTertiary; l.isHidden = true
        return l
    }()

    private var shareBarItem: UIBarButtonItem?

    deinit { disposables.dispose() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        updateTitle()


        tableView.tableHeaderView = searchBar
        searchBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 44)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear", style: .plain, target: self, action: #selector(clearAll)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemRed

        let shareItem: UIBarButtonItem
        if #available(iOS 13, *) {
            shareItem = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain, target: self, action: #selector(shareTapped)
            )
        } else {
            shareItem = UIBarButtonItem(
                title: "Share", style: .plain, target: self, action: #selector(shareTapped)
            )
        }
        self.shareBarItem = shareItem
        navigationItem.leftBarButtonItem = shareItem

        [tableView, emptyLabel].forEach {
            view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        disposables += tracker.chains.producer
            .observe(on: UIScheduler())
            .startWithValues { [weak self] chains in
                guard let self = self else { return }
                self.chains = chains
                self.applyFilter()
                self.updateTitle()
            }
    }

    private func updateTitle() {
        let envSegment = APILogExporter.environment(tracker: tracker).map { " \($0)" } ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

        let label = UILabel()
        label.numberOfLines = 2
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail

        let firstLine = "API Logs\(envSegment)"
        let secondLine = "(\(version) #\(build))"
        let attributed = NSMutableAttributedString(
            string: firstLine,
            attributes: [.font: UIFont.boldSystemFont(ofSize: 16)]
        )
        attributed.append(NSAttributedString(
            string: "\n\(secondLine)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.compatTertiary
            ]
        ))
        label.attributedText = attributed
        label.sizeToFit()

        navigationItem.titleView = label
    }

    private func applyFilter() {
        let query = searchBar.text ?? ""
        filtered = query.isEmpty ? chains : chains.filter { $0.tag.localizedCaseInsensitiveContains(query) }
        emptyLabel.isHidden = !filtered.isEmpty
        tableView.reloadData()
    }

    @objc private func clearAll() {
        let alert = UIAlertController(title: "Clear all logs?", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.tracker.clearAll()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func shareTapped() {
        let allChains = tracker.chains.value
        guard !allChains.isEmpty else { return }

        let coordinator = ExportShareCoordinator(
            formats: uiConfiguration.exportFormats,
            barButton: shareBarItem,
            plainText: { [weak self] in
                guard let self else { return (name: "", content: "") }
                let content = APILogExporter.exportAll(chains: allChains, insights: self.uiConfiguration.insights)
                return (name: APILogExporter.allLogsFileName, content: content)
            },
            markdown: { [weak self] in
                guard let self else { return (name: "", content: "") }
                let content = APILogExporter.exportAllMarkdownCollapsible(chains: allChains, insights: self.uiConfiguration.insights)
                return (name: APILogExporter.allLogsMarkdownFileName, content: content)
            },
            bruno: { APILogExporter.exportBrunoCollection(chains: allChains) }
        )
        coordinator.present(from: self)
    }
}

extension APILogsPanelVC: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    public func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: ChainCell.reuseID, for: indexPath) as! ChainCell
        cell.configure(with: filtered[indexPath.row], insights: uiConfiguration.insights)
        return cell
    }

    public func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        let detail = ChainDetailVC(
            chain: filtered[indexPath.row],
            tracker: tracker,
            uiConfiguration: uiConfiguration
        )
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension APILogsPanelVC: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter()
        if searchText.isEmpty {
            DispatchQueue.main.async {
                searchBar.resignFirstResponder()
            }
        }
    }
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}
