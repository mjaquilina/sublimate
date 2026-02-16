import Foundation
import GRDB

/// Generates sample data for testing the application
class SampleDataGenerator {

    /// Generate a full set of sample data
    static func generate() throws {
        let db = try DatabaseManager.shared.database()
        let engine = RewardCalculationEngine(database: db)

        // 1. Categories (use existing ones from migration, but ensure they exist)
        let categories = try DatabaseManager.shared.read { db in
            try Category.fetchAll(db)
        }
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })

        // 2. Vendors
        let vendorData: [(name: String, displayName: String, category: String?)] = [
            ("chipotle", "Chipotle", "Dining"),
            ("whole foods", "Whole Foods", "Groceries"),
            ("shell", "Shell", "Gas"),
            ("united airlines", "United Airlines", "Travel"),
            ("amazon", "Amazon", "Shopping"),
        ]

        var vendorMap: [String: Vendor] = [:]
        try DatabaseManager.shared.write { db in
            for v in vendorData {
                let categoryId = categoryMap[v.category ?? ""]?.id
                let vendor = Vendor(name: v.name, displayName: v.displayName, defaultCategoryId: categoryId)
                try vendor.insert(db)
                vendorMap[v.name] = vendor
            }
        }

        // 3. Cards
        let csr = Card(name: "Chase Sapphire Reserve", issuer: "Chase", lastFour: "4567")
        let amexGold = Card(name: "Amex Gold", issuer: "American Express", lastFour: "1234")
        let ventureX = Card(name: "Capital One Venture X", issuer: "Capital One", lastFour: "8901")

        try DatabaseManager.shared.write { db in
            try csr.insert(db)
            try amexGold.insert(db)
            try ventureX.insert(db)
        }

        // 4. Point Types
        let ur = PointType(cardId: csr.id, name: "Ultimate Rewards", cashValuePerPoint: Decimal(string: "0.015")!)
        let mr = PointType(cardId: amexGold.id, name: "Membership Rewards", cashValuePerPoint: Decimal(string: "0.02")!)
        let miles = PointType(cardId: ventureX.id, name: "Venture Miles", cashValuePerPoint: Decimal(string: "0.01")!)

        try DatabaseManager.shared.write { db in
            try ur.insert(db)
            try mr.insert(db)
            try miles.insert(db)
        }

        // 5. Point Balances
        try DatabaseManager.shared.write { db in
            try PointBalance(pointTypeId: ur.id, balance: 50000).insert(db)
            try PointBalance(pointTypeId: mr.id, balance: 75000).insert(db)
            try PointBalance(pointTypeId: miles.id, balance: 30000).insert(db)
        }

        // 6. Earning Rules
        // CSR: 3x dining, 3x travel, 1x all spend
        let csrDining = EarningRule(cardId: csr.id, pointTypeId: ur.id, name: "3x Dining", matchType: .category, matchValues: ["Dining"], pointsPerDollar: 3)
        let csrTravel = EarningRule(cardId: csr.id, pointTypeId: ur.id, name: "3x Travel", matchType: .category, matchValues: ["Travel"], pointsPerDollar: 3)
        let csrBase = EarningRule(cardId: csr.id, pointTypeId: ur.id, name: "1x All Spend", matchType: .allSpend, matchValues: [], pointsPerDollar: 1)

        // Amex Gold: 4x dining, 4x groceries, 1x all spend
        let amexDining = EarningRule(cardId: amexGold.id, pointTypeId: mr.id, name: "4x Dining", matchType: .category, matchValues: ["Dining"], pointsPerDollar: 4)
        let amexGroceries = EarningRule(cardId: amexGold.id, pointTypeId: mr.id, name: "4x Groceries", matchType: .category, matchValues: ["Groceries"], pointsPerDollar: 4)
        let amexBase = EarningRule(cardId: amexGold.id, pointTypeId: mr.id, name: "1x All Spend", matchType: .allSpend, matchValues: [], pointsPerDollar: 1)

        // Venture X: 2x all spend
        let ventureBase = EarningRule(cardId: ventureX.id, pointTypeId: miles.id, name: "2x All Spend", matchType: .allSpend, matchValues: [], pointsPerDollar: 2)

        try DatabaseManager.shared.write { db in
            try csrDining.insert(db)
            try csrTravel.insert(db)
            try csrBase.insert(db)
            try amexDining.insert(db)
            try amexGroceries.insert(db)
            try amexBase.insert(db)
            try ventureBase.insert(db)
        }

        // 7. Earning Caps
        let now = Date()
        let quarterStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .quarter], from: now))
            ?? now.startOfMonth()
        let quarterEnd = Calendar.current.date(byAdding: .month, value: 3, to: quarterStart) ?? now

        let yearStart = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: now)) ?? now
        let yearEnd = Calendar.current.date(byAdding: .year, value: 1, to: yearStart) ?? now

        let csrCap = EarningCap(name: "CSR Gas+Groceries $1,500/Quarter", maxSpend: 1500, startDate: quarterStart, endDate: quarterEnd)
        let amexCap = EarningCap(name: "Amex Gold Groceries $25,000/Year", maxSpend: 25000, startDate: yearStart, endDate: yearEnd)

        try DatabaseManager.shared.write { db in
            try csrCap.insert(db)
            try amexCap.insert(db)

            // Link caps to rules
            try EarningRuleCap(earningRuleId: csrBase.id, earningCapId: csrCap.id).insert(db)
            try EarningRuleCap(earningRuleId: amexGroceries.id, earningCapId: amexCap.id).insert(db)
        }

        // 8. Spend Offers (one of each type)
        let offerStart = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let offerEnd = Calendar.current.date(byAdding: .month, value: 2, to: now) ?? now

        let percentOffer = SpendOffer(
            cardId: csr.id, name: "5% Back on Dining", offerType: .percentageBack,
            matchType: .category, matchValues: ["Dining"],
            rewardPercentage: 5, maxRewardAmount: 25,
            startDate: offerStart, endDate: offerEnd
        )

        let thresholdOffer = SpendOffer(
            cardId: amexGold.id, name: "Spend $500, Get $50", offerType: .flatBonusSpendThreshold,
            matchType: .vendor, matchValues: ["Whole Foods"],
            flatBonusAmount: 50, spendThreshold: 500, pointTypeId: mr.id,
            startDate: offerStart, endDate: offerEnd
        )

        let countOffer = SpendOffer(
            cardId: ventureX.id, name: "5 Purchases, Get 1000 Miles", offerType: .flatBonusTransactionCount,
            matchType: .allSpend, matchValues: [],
            flatBonusAmount: 1000, countRequired: 5, transactionMinAmount: 10, pointTypeId: miles.id,
            startDate: offerStart, endDate: offerEnd
        )

        try DatabaseManager.shared.write { db in
            try percentOffer.insert(db)
            try thresholdOffer.insert(db)
            try countOffer.insert(db)
        }

        // 9. Rebates
        let rebateEnd = Calendar.current.date(byAdding: .month, value: 3, to: now)

        let chipotleRebate = Rebate(
            cardId: amexGold.id, vendor: "Chipotle", rebateType: .fixed,
            rebateValue: 10, maxUses: 3, startDate: offerStart, endDate: rebateEnd
        )
        let shellRebate = Rebate(
            cardId: csr.id, vendor: "Shell", rebateType: .percentage,
            rebateValue: 10, maxAmount: 5, maxUses: 5, startDate: offerStart, endDate: rebateEnd
        )
        let amazonRebate = Rebate(
            cardId: ventureX.id, vendor: "Amazon", rebateType: .percentage,
            rebateValue: 5, maxAmount: 25, startDate: offerStart, endDate: rebateEnd
        )

        try DatabaseManager.shared.write { db in
            try chipotleRebate.insert(db)
            try shellRebate.insert(db)
            try amazonRebate.insert(db)
        }

        // 10. Transactions (15-20 across the cards, last 60 days)
        struct TxData {
            let cardId: UUID
            let vendor: String
            let category: String?
            let amount: Decimal
            let daysAgo: Int
        }

        let txData: [TxData] = [
            // CSR transactions
            TxData(cardId: csr.id, vendor: "Chipotle", category: "Dining", amount: Decimal(string: "14.50")!, daysAgo: 2),
            TxData(cardId: csr.id, vendor: "United Airlines", category: "Travel", amount: Decimal(string: "350.00")!, daysAgo: 5),
            TxData(cardId: csr.id, vendor: "Shell", category: "Gas", amount: Decimal(string: "45.80")!, daysAgo: 8),
            TxData(cardId: csr.id, vendor: "Amazon", category: "Shopping", amount: Decimal(string: "89.99")!, daysAgo: 12),
            TxData(cardId: csr.id, vendor: "Chipotle", category: "Dining", amount: Decimal(string: "16.25")!, daysAgo: 18),
            TxData(cardId: csr.id, vendor: "Shell", category: "Gas", amount: Decimal(string: "52.30")!, daysAgo: 30),

            // Amex Gold transactions
            TxData(cardId: amexGold.id, vendor: "Chipotle", category: "Dining", amount: Decimal(string: "12.75")!, daysAgo: 1),
            TxData(cardId: amexGold.id, vendor: "Whole Foods", category: "Groceries", amount: Decimal(string: "156.42")!, daysAgo: 3),
            TxData(cardId: amexGold.id, vendor: "Whole Foods", category: "Groceries", amount: Decimal(string: "87.30")!, daysAgo: 10),
            TxData(cardId: amexGold.id, vendor: "Chipotle", category: "Dining", amount: Decimal(string: "15.99")!, daysAgo: 15),
            TxData(cardId: amexGold.id, vendor: "Whole Foods", category: "Groceries", amount: Decimal(string: "203.18")!, daysAgo: 22),
            TxData(cardId: amexGold.id, vendor: "Amazon", category: "Shopping", amount: Decimal(string: "42.50")!, daysAgo: 35),

            // Venture X transactions
            TxData(cardId: ventureX.id, vendor: "Amazon", category: "Shopping", amount: Decimal(string: "129.99")!, daysAgo: 4),
            TxData(cardId: ventureX.id, vendor: "Shell", category: "Gas", amount: Decimal(string: "38.50")!, daysAgo: 7),
            TxData(cardId: ventureX.id, vendor: "United Airlines", category: "Travel", amount: Decimal(string: "225.00")!, daysAgo: 14),
            TxData(cardId: ventureX.id, vendor: "Chipotle", category: "Dining", amount: Decimal(string: "13.80")!, daysAgo: 20),
            TxData(cardId: ventureX.id, vendor: "Amazon", category: "Shopping", amount: Decimal(string: "67.45")!, daysAgo: 28),
            TxData(cardId: ventureX.id, vendor: "Whole Foods", category: "Groceries", amount: Decimal(string: "95.60")!, daysAgo: 40),
        ]

        for tx in txData {
            let date = Calendar.current.date(byAdding: .day, value: -tx.daysAgo, to: now) ?? now
            let transaction = Transaction(
                cardId: tx.cardId,
                date: date,
                vendor: tx.vendor,
                merchantCategory: tx.category,
                amount: tx.amount,
                transactionType: .purchase,
                rewardEligible: true
            )

            // Calculate and save rewards
            let preview = try engine.calculateTransactionRewards(transaction)
            try engine.saveTransactionWithRewards(transaction, preview: preview)
        }
    }
}
