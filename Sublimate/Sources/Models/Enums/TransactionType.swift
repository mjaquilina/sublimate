import Foundation

/// Type of transaction
enum TransactionType: String, Codable {
    case purchase = "purchase"
    case refund = "refund"
    case payment = "payment"
    case statementCredit = "statement_credit"
    case fee = "fee"
}
