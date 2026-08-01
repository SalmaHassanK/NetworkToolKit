import Foundation
import NetworkInspector

class APIClient {
    
    private let session: URLSession
    
    init() {
        // Create a session through NetworkInspector
        self.session = NetworkInspector.shared.makeSession(
            configuration: .default,
            forwardingTo: nil
        )
    }
    
    // MARK: - Sync Request
    
    func makeSyncRequest(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1") else {
            completion(.failure(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Make sync request with NetworkInspector
        let task = session.dataTask(
            with: request,
            inspection: .init(
                tag: "GET /posts/1",
                mode: .sync  // Auto-closes chain when complete
            )
        ) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            let statusCode = httpResponse.statusCode
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String {
                completion(.success("Status: \(statusCode)\nTitle: \(title)"))
            } else {
                completion(.success("Status: \(statusCode)\nReceived data: \(data.count) bytes"))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Async Request (Simulating multi-stage flow with fallback)
    
    func makeAsyncRequest(completion: @escaping (Result<String, Error>) -> Void) {
        let correlationId = UUID().uuidString
        
        // Use a non-existent endpoint to reliably trigger 404 error
        // This simulates a primary endpoint that fails
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/nonexistent-endpoint-999") else {
            completion(.failure(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        // Async mode with terminal condition checking
        let mode = RequestMode.async(maxOpenInterval: 60) { attempt in
            // Check if this attempt is terminal
            guard let statusCode = attempt.statusCode else {
                return false  // Transport error, keep chain open for fallback
            }
            
            // Only 2xx responses are terminal, everything else keeps chain open
            return (200..<300).contains(statusCode)
        }
        
        let task = session.dataTask(
            with: request,
            inspection: .init(
                correlationId: correlationId,
                tag: "Primary Request (will fail)",
                mode: mode
            )
        ) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                // Network error - trigger fallback
                print("⚠️ Primary request network error: \(error.localizedDescription)")
                print("🔄 Triggering fallback request...")
                
                // Trigger fallback on the same chain
                self.makeFallbackRequest(correlationId: correlationId) { fallbackResult in
                    switch fallbackResult {
                    case .success(let message):
                        completion(.success("❌ Primary: Network Error\n✅ Fallback: Succeeded\n\n\(message)"))
                    case .failure(let fallbackError):
                        completion(.failure(fallbackError))
                    }
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            let statusCode = httpResponse.statusCode
            
            // Check if we should retry with fallback (4xx or 5xx errors)
            if statusCode >= 400 {
                print("⚠️ Primary returned \(statusCode), triggering fallback...")
                
                // Trigger fallback on the same chain
                self.makeFallbackRequest(correlationId: correlationId) { fallbackResult in
                    switch fallbackResult {
                    case .success(let message):
                        completion(.success("❌ Primary: HTTP \(statusCode)\n✅ Fallback: Succeeded\n\n\(message)"))
                    case .failure(let fallbackError):
                        completion(.failure(fallbackError))
                    }
                }
            } else if (200..<300).contains(statusCode) {
                // Success on primary (shouldn't happen with our demo endpoint)
                completion(.success("✅ Primary request succeeded on first try!\nStatus: \(statusCode)"))
            } else {
                completion(.failure(NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Fallback Request (demonstrates chain continuation)
    
    private func makeFallbackRequest(correlationId: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Fallback to a reliable endpoint
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/users/1") else {
            completion(.failure(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        // Same terminal condition as primary
        let mode = RequestMode.async(maxOpenInterval: 30) { attempt in
            guard let statusCode = attempt.statusCode else {
                return false
            }
            return (200..<300).contains(statusCode)
        }
        
        let task = session.dataTask(
            with: request,
            inspection: .init(
                correlationId: correlationId,  // Same ID = same chain, kind auto-inferred as fallback!
                tag: "Fallback Request",
                mode: mode
            )
        ) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            let statusCode = httpResponse.statusCode
            
            if (200..<300).contains(statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["name"] as? String,
                   let email = json["email"] as? String {
                    completion(.success("Fallback Status: \(statusCode)\nName: \(name)\nEmail: \(email)"))
                } else {
                    completion(.success("Fallback Status: \(statusCode)\nReceived data: \(data.count) bytes"))
                }
            } else {
                completion(.failure(NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Fallback also failed with HTTP \(statusCode)"])))
            }
        }
        
        task.resume()
    }
}
