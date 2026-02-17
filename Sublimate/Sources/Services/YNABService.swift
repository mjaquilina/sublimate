import Foundation

/// YNAB API models
struct YNABBudget: Codable, Identifiable {
    let id: String
    let name: String
}

struct YNABAccount: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let balance: Int
    let closed: Bool
}

struct YNABTransaction: Codable, Identifiable {
    let id: String
    let date: String
    let amount: Int  // In milliunits
    let memo: String?
    let cleared: String
    let approved: Bool
    let payeeName: String?
    let categoryName: String?
    let accountId: String
}

struct YNABBudgetResponse: Codable {
    let data: YNABBudgetsData
}

struct YNABBudgetsData: Codable {
    let budgets: [YNABBudget]
}

struct YNABAccountsResponse: Codable {
    let data: YNABAccountsData
}

struct YNABAccountsData: Codable {
    let accounts: [YNABAccount]
}

struct YNABTransactionsResponse: Codable {
    let data: YNABTransactionsData
}

struct YNABTransactionsData: Codable {
    let transactions: [YNABTransaction]
}

/// Service for communicating with the YNAB API
class YNABService {
    static let shared = YNABService()

    private let baseURL = "https://api.ynab.com/v1"
    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - Authentication

    func authenticateWithToken(_ token: String) async throws -> Bool {
        _ = keychain.saveYNABToken(token)

        // Test the token by fetching budgets
        _ = try await fetchBudgets()
        return true
    }

    func isAuthenticated() -> Bool {
        return keychain.getYNABToken() != nil
    }

    func logout() {
        _ = keychain.deleteYNABToken()
    }

    // MARK: - API Requests

    func fetchBudgets() async throws -> [YNABBudget] {
        let response: YNABBudgetResponse = try await request(endpoint: "/budgets")
        return response.data.budgets
    }

    func fetchAccounts(budgetId: String) async throws -> [YNABAccount] {
        let response: YNABAccountsResponse = try await request(endpoint: "/budgets/\(budgetId)/accounts")
        return response.data.accounts.filter { !$0.closed }
    }

    func fetchTransactions(budgetId: String, accountId: String, sinceDate: Date? = nil) async throws -> [YNABTransaction] {
        var endpoint = "/budgets/\(budgetId)/accounts/\(accountId)/transactions"

        if let sinceDate = sinceDate {
            // Format date in local timezone to avoid off-by-one errors
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            let dateString = formatter.string(from: sinceDate)
            endpoint += "?since_date=\(dateString)"
        }

        let response: YNABTransactionsResponse = try await request(endpoint: endpoint)

        // Filter to only cleared or reconciled transactions
        return response.data.transactions.filter {
            $0.cleared == "cleared" || $0.cleared == "reconciled"
        }
    }

    // MARK: - Private Methods

    private func request<T: Decodable>(endpoint: String) async throws -> T {
        guard let token = keychain.getYNABToken() else {
            throw YNABError.notAuthenticated
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw YNABError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as NSError {
            // Handle network-specific errors
            switch error.code {
            case NSURLErrorNotConnectedToInternet:
                throw YNABError.networkError("No internet connection. Please check your network settings.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                throw YNABError.networkError("Cannot reach YNAB servers. This may be due to app sandbox restrictions. Please ensure the app has network permissions in System Settings > Privacy & Security.")
            case NSURLErrorTimedOut:
                throw YNABError.networkError("Connection timed out. Please check your internet connection and try again.")
            case NSURLErrorSecureConnectionFailed:
                throw YNABError.networkError("Secure connection failed. Please check your network configuration.")
            default:
                throw YNABError.networkError("Network error: \(error.localizedDescription)")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YNABError.invalidResponse
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw YNABError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            throw YNABError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw YNABError.decodingError(error)
        }
    }

    // MARK: - Transaction Classification

    func classifyTransactionType(amount: Int, memo: String?, payeeName: String?) -> TransactionType {
        let amountInDollars = Decimal(amount) / 1000

        // Negative amount = purchase
        if amountInDollars < 0 {
            return .purchase
        }

        // Positive amounts - check memo/payee for clues
        let text = "\(memo ?? "") \(payeeName ?? "")".lowercased()

        if text.contains("payment") {
            return .payment
        } else if text.contains("refund") {
            return .refund
        } else if text.contains("credit") || text.contains("reward") || text.contains("cashback") {
            return .statementCredit
        } else if text.contains("fee") {
            return .fee
        } else {
            // Default positive amounts to statement credit with review flag
            return .statementCredit
        }
    }

    func convertAmount(_ milliunits: Int) -> Decimal {
        // YNAB uses negative for outflows (purchases) and positive for inflows (payments/credits)
        // We invert this: purchases are positive, payments/credits are negative
        return -(Decimal(milliunits) / 1000)
    }
}

// MARK: - Errors

enum YNABError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case rateLimitExceeded
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with YNAB. Please provide an API token."
        case .invalidURL:
            return "Invalid URL for YNAB API request."
        case .invalidResponse:
            return "Invalid response from YNAB API."
        case .rateLimitExceeded:
            return "YNAB API rate limit exceeded. Please wait and try again."
        case .httpError(let statusCode):
            return "HTTP error \(statusCode) from YNAB API."
        case .decodingError(let error):
            return "Failed to decode YNAB API response: \(error.localizedDescription)"
        case .networkError(let message):
            return message
        }
    }
}
