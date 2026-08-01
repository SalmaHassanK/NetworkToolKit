import UIKit
import NetworkToolKit

class MainViewController: UIViewController {
    
    private let apiClient = APIClient()
    private var floatingButton: UIButton!
    
    // MARK: - UI Components
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "NetworkInspector Demo"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let syncButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Make Sync Request", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let asyncButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Make Async Request (with Fallback)", for: .normal)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let responseLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap a button to make a request"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .gray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView()
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFloatingButton()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Demo App"
        
        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(syncButton)
        view.addSubview(asyncButton)
        view.addSubview(responseLabel)
        view.addSubview(activityIndicator)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            syncButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 60),
            syncButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            syncButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            syncButton.heightAnchor.constraint(equalToConstant: 60),
            
            asyncButton.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 20),
            asyncButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            asyncButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            asyncButton.heightAnchor.constraint(equalToConstant: 60),
            
            responseLabel.topAnchor.constraint(equalTo: asyncButton.bottomAnchor, constant: 40),
            responseLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            responseLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            activityIndicator.topAnchor.constraint(equalTo: responseLabel.bottomAnchor, constant: 20),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        // Add button actions
        syncButton.addTarget(self, action: #selector(syncButtonTapped), for: .touchUpInside)
        asyncButton.addTarget(self, action: #selector(asyncButtonTapped), for: .touchUpInside)
    }
    
    private func setupFloatingButton() {
        floatingButton = UIButton(type: .custom)
        floatingButton.backgroundColor = .white
        if #available(iOS 13.0, *) {
            floatingButton.setImage(.init(systemName: "document"), for: .normal)
        } else {
            // Fallback on earlier versions
        }
        floatingButton.titleLabel?.font = UIFont.systemFont(ofSize: 30)
        floatingButton.layer.cornerRadius = 30
        floatingButton.layer.shadowColor = UIColor.black.cgColor
        floatingButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        floatingButton.layer.shadowOpacity = 0.3
        floatingButton.layer.shadowRadius = 4
        floatingButton.translatesAutoresizingMaskIntoConstraints = false
        floatingButton.addTarget(self, action: #selector(floatingButtonTapped), for: .touchUpInside)
        
        view.addSubview(floatingButton)
        
        NSLayoutConstraint.activate([
            floatingButton.widthAnchor.constraint(equalToConstant: 60),
            floatingButton.heightAnchor.constraint(equalToConstant: 60),
            floatingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            floatingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func syncButtonTapped() {
        activityIndicator.startAnimating()
        responseLabel.text = "Making sync request..."
        responseLabel.textColor = .gray
        
        apiClient.makeSyncRequest { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.handleResponse(result, type: "Sync")
            }
        }
    }
    
    @objc private func asyncButtonTapped() {
        activityIndicator.startAnimating()
        responseLabel.text = "Making async request...\n\n1️⃣ Primary will fail (404)\n2️⃣ Fallback will succeed (200)\n\nTap 📊 to see both in one chain!"
        responseLabel.textColor = .systemOrange
        
        apiClient.makeAsyncRequest { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.handleResponse(result, type: "Multi-Stage")
            }
        }
    }
    
    @objc private func floatingButtonTapped() {
        let inspectorVC = NetworkInspector.shared.viewController()
        let navController = UINavigationController(rootViewController: inspectorVC)
//        navController.modalPresentationStyle = .overFullScreen
        present(navController, animated: true)
    }
    
    // MARK: - Helpers
    
    private func handleResponse(_ result: Result<String, Error>, type: String) {
        switch result {
        case .success(let message):
            responseLabel.text = "✅ \(type) Request Success!\n\n\(message)"
            responseLabel.textColor = .systemGreen
            
        case .failure(let error):
            responseLabel.text = "❌ \(type) Request Failed!\n\n\(error.localizedDescription)"
            responseLabel.textColor = .systemRed
        }
    }
}
