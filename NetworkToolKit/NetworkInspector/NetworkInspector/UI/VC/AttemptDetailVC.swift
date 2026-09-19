//
//  AttemptDetailVC.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 24/03/2026.
//
// Detail screen for a single ``APIAttempt``.
//
// ## HTTP requests
// Shows a stat bar (attempt label, duration, business status) and a segmented control
// to switch between the **Request** tab (URL, request headers, request body) and the
// **Response** tab (response headers, response body).
//
// ## External completions (push / polling)
// Shows only the payload section — no stat bar or request/response tabs.
//
// ## Large-body handling
// Bodies larger than 64 KB are truncated with a visible warning banner to prevent
// the UI from hanging on multi-megabyte payloads.

import UIKit

/// Displays the full request/response detail for a single network attempt.
///
/// Pushed from ``ChainDetailVC`` when the user taps an attempt row.
final class AttemptDetailVC: UIViewController {

    private let attempt: AttemptDisplayable

    // Only shown for HTTP requests
    private lazy var segmented: UISegmentedControl = {
        let s = UISegmentedControl(items: ["Request", "Response"])
        s.selectedSegmentIndex = 0
        if #available(iOS 13, *) { s.selectedSegmentTintColor = .systemBlue }
        s.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        s.setTitleTextAttributes([.foregroundColor: UIColor.systemBlue], for: .normal)
        s.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return s
    }()

    private lazy var tableView: UITableView = {
        let tv = makeTableView()
        tv.register(KeyValueCell.self, forCellReuseIdentifier: KeyValueCell.reuseID)
        tv.register(MonoCell.self,     forCellReuseIdentifier: MonoCell.reuseID)
        tv.dataSource = self
        tv.rowHeight  = UITableView.automaticDimension
        tv.estimatedRowHeight = 44
        return tv
    }()

    init(attempt: AttemptDisplayable) {
        self.attempt = attempt
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title      = attempt.label
        view.backgroundColor = .compatGroupedBg

        // Stat bar + request/response segmented for HTTP; nothing for push.
        let headerView: UIView = attempt.isExternalCompletion ? UIView() : makeHTTPHeader()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        view.addSubview(headerView)
        view.addSubview(tableView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints  = false
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func segmentChanged() { tableView.reloadData() }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let cell = tableView.cellForRow(at: indexPath) else { return }

        let text: String
        if let kvCell = cell as? KeyValueCell {
            text = "\(kvCell.keyLabel.text ?? ""): \(kvCell.valueLabel.text ?? "")"
        }
        else if let monoCell = cell as? MonoCell {
            text = monoCell.copyableText
        } else {
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

    // MARK: HTTP header (stat bar + fallback banner + segmented)

    private func makeHTTPHeader() -> UIView {
        let segWrapper = UIView()
        segWrapper.addSubview(segmented)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: segWrapper.topAnchor, constant: 10),
            segmented.bottomAnchor.constraint(equalTo: segWrapper.bottomAnchor, constant: -10),
            segmented.leadingAnchor.constraint(equalTo: segWrapper.leadingAnchor, constant: 16),
            segmented.trailingAnchor.constraint(equalTo: segWrapper.trailingAnchor, constant: -16),
        ])

        let stack = UIStackView(arrangedSubviews: [makeStatBar(), segWrapper])
        stack.axis = .vertical; stack.spacing = 0
        return stack
    }

    private func makeStatBar() -> UIView {
        let container = UIView()
        container.backgroundColor = .compatSecondaryGroupedBg

        func stat(_ label: String, _ value: String, color: UIColor = .compatLabel) -> UIView {
            let l = UILabel(); l.text = label; l.font = .systemFont(ofSize: 10); l.textColor = .compatTertiary
            let v = UILabel(); v.text = value; v.font = .systemFont(ofSize: 13, weight: .medium); v.textColor = color
            let s = UIStackView(arrangedSubviews: [l, v]); s.axis = .vertical; s.alignment = .center; s.spacing = 2
            return s
        }
        func divider() -> UIView {
            let v = UIView(); v.backgroundColor = .compatSeparator
            v.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
            v.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return v
        }

        let attemptColor: UIColor = attempt.index == 0 ? .systemBlue : .systemOrange

        let stack = UIStackView(arrangedSubviews: [
            stat("Attempt", attempt.label, color: attemptColor), divider(),
            stat("Duration", attempt.durationString), divider(),
            stat("HTTP Status", attempt.httpStatusCode.map { "\($0)" } ?? "—", color: .systemBlue)
        ])
        stack.axis = .horizontal; stack.distribution = .equalSpacing; stack.alignment = .center

        container.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])

        let sep = UIView(); sep.backgroundColor = .compatSeparator
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        container.addSubview(sep); sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - Data helpers

    private var httpHeaders: [String: String] {
        segmented.selectedSegmentIndex == 0
        ? attempt.requestHeaders
        : attempt.responseHeaders ?? [:]
    }

    /// Bodies larger than this are truncated to avoid UI hangs.
    private static let maxPreviewBytes = 32 * 1024 // 32 KB

    private var httpBody: String? {
        if segmented.selectedSegmentIndex == 0 {
            guard let data = attempt.requestBody, !data.isEmpty else { return nil }
            return Self.prettyPrintedBody(from: data, isRequest: true)
        } else {
            guard let response = attempt.responseBody, !response.isEmpty else { return nil }
            guard let data = response.data(using: .utf8) else { return response }
            return Self.prettyPrintedBody(from: data, isRequest: false)
        }
    }

    private static func prettyPrintedBody(from data: Data, isRequest: Bool) -> String {
        let sizeString = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory)
        let isTruncated = data.count > maxPreviewBytes

        let workingData = isTruncated ? data.prefix(maxPreviewBytes) : data
        let warningMessage = isRequest ? "Large request" : "Large response"

        let header = isTruncated ? "⚠️ \(warningMessage) (\(sizeString)) — preview only shown\n\n" : ""

        if let json   = try? JSONSerialization.jsonObject(with: workingData),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let text   = String(data: pretty, encoding: .utf8) {
            return header + text + (isTruncated ? "\n\n⚠️ … truncated" : "")
        }

        if let text = String(data: workingData, encoding: .utf8) {
            return header + text + (isTruncated ? "\n\n⚠️ … truncated" : "")
        }

        return "⚠️ Encrypted / Binary — \(sizeString)"
    }

    private var prettyPushPayload: String {
        guard let body = attempt.responseBody,
              let data = body.data(using: .utf8) else { return attempt.responseBody ?? "" }
        return Self.prettyPrintedBody(from: data, isRequest: false)
    }
}

extension AttemptDetailVC: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        if attempt.isExternalCompletion { return 1 }   // payload only
        return segmented.selectedSegmentIndex == 0 ? 3 : 2
    }

    func tableView(_ tv: UITableView, titleForHeaderInSection section: Int) -> String? {
        if attempt.isExternalCompletion { return "Payload" }
        return segmented.selectedSegmentIndex == 0
        ? ["URL", "Request headers", "Request body"][section]
        : ["Response headers", "Response body"][section]
    }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        if attempt.isExternalCompletion { return 1 }
        let logical = segmented.selectedSegmentIndex == 0 ? section : section + 1
        switch logical {
        case 0:  return 1
        case 1:  return max(1, httpHeaders.count)
        case 2:  return 1
        default: return 0
        }
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        attempt.isExternalCompletion
        ? pushCell(at: indexPath, in: tv)
        : httpCell(at: indexPath, in: tv)
    }

    // MARK: HTTP cells

    private func httpCell(at indexPath: IndexPath, in tv: UITableView) -> UITableViewCell {
        let logical = segmented.selectedSegmentIndex == 0 ? indexPath.section : indexPath.section + 1
        switch logical {
        case 0:
            let cell = tv.dequeueReusableCell(withIdentifier: MonoCell.reuseID, for: indexPath) as! MonoCell
            let method = attempt.requestHTTPMethod
            let url = attempt.requestURL
            let methodColor: UIColor = {
                switch method {
                case "GET":    return .systemGreen
                case "POST":   return .systemBlue
                case "PUT":    return .systemOrange
                case "DELETE": return .systemRed
                case "PATCH":  return .systemPurple
                default:       return .compatLabel
                }
            }()
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: method, attributes: [
                .font: UIFont.monoFont(ofSize: 12, weight: .bold),
                .foregroundColor: methodColor
            ]))
            attr.append(NSAttributedString(string: "  \(url)", attributes: [
                .font: UIFont.monoFont(ofSize: 11),
                .foregroundColor: UIColor.compatLabel
            ]))
            cell.configure(attributed: attr)
            return cell
        case 1:
            let sorted = httpHeaders.sorted { $0.key < $1.key }
            let cell   = tv.dequeueReusableCell(withIdentifier: KeyValueCell.reuseID, for: indexPath) as! KeyValueCell
            if sorted.isEmpty { cell.configure(key: "—", value: "Empty", valueIsEmpty: true) }
            else { let (k, v) = sorted[indexPath.row]; cell.configure(key: k, value: v) }
            return cell
        case 2:
            let cell = tv.dequeueReusableCell(withIdentifier: MonoCell.reuseID, for: indexPath) as! MonoCell
            cell.configure(text: httpBody ?? "Empty")
            return cell
        default: return UITableViewCell()
        }
    }

    // MARK: Push cells

    private func pushCell(at indexPath: IndexPath, in tv: UITableView) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: MonoCell.reuseID, for: indexPath) as! MonoCell
        cell.configure(text: prettyPushPayload)
        return cell
    }
}
