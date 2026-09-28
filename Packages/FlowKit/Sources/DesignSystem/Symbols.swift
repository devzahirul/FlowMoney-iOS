public import Domain
public import SwiftUI

/// Visual identity (SF Symbol + color) for domain values. Lives in the UI layer so `Domain` stays UI-free.
public extension Domain.Category {
    var symbol: String {
        switch id {
        case .food: "fork.knife"
        case .groceries: "cart.fill"
        case .shopping: "bag.fill"
        case .transport: "car.fill"
        case .travel: "airplane"
        case .bills: "bolt.fill"
        case .housing: "house.fill"
        case .entertainment: "popcorn.fill"
        case .subscriptions: "play.rectangle.fill"
        case .health: "heart.fill"
        case .education: "graduationcap.fill"
        case .personal: "person.fill"
        case .gifts, .giftsReceived: "gift.fill"
        case .salary: "banknote.fill"
        case .freelance: "laptopcomputer"
        case .investmentIncome: "chart.line.uptrend.xyaxis"
        case .otherIncome: "plus.circle.fill"
        default: "square.grid.2x2.fill"
        }
    }

    var color: Color {
        let index = CategoryCatalog.all.firstIndex { $0.id == id } ?? (Theme.palette.count - 1)
        return Theme.palette[index % Theme.palette.count]
    }
}

public extension AccountKind {
    var symbol: String {
        switch self {
        case .checking: "building.columns.fill"
        case .savings: "banknote.fill"
        case .cash: "dollarsign.circle.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .property: "house.fill"
        case .creditCard: "creditcard.fill"
        case .loan: "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking: Theme.palette[2]
        case .savings: Theme.palette[4]
        case .cash: Theme.palette[5]
        case .investment: Theme.palette[1]
        case .property: Theme.palette[0]
        case .creditCard: Theme.palette[6]
        case .loan: Theme.palette[8]
        }
    }
}

public extension GoalSymbol {
    var symbol: String {
        switch self {
        case .vacation: "airplane"
        case .car: "car.fill"
        case .home: "house.fill"
        case .emergency: "cross.case.fill"
        case .education: "graduationcap.fill"
        case .wedding: "heart.fill"
        case .gadget: "laptopcomputer"
        case .other: "star.fill"
        }
    }

    var title: String {
        switch self {
        case .vacation: "Travel"
        case .car: "Car"
        case .home: "Home"
        case .emergency: "Emergency"
        case .education: "Education"
        case .wedding: "Wedding"
        case .gadget: "Gadget"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .vacation: Theme.palette[2]
        case .car: Theme.palette[0]
        case .home: Theme.palette[7]
        case .emergency: Theme.palette[8]
        case .education: Theme.palette[6]
        case .wedding: Theme.palette[3]
        case .gadget: Theme.palette[1]
        case .other: Theme.palette[5]
        }
    }
}

public extension Insight.Tone {
    var color: Color {
        switch self {
        case .positive: Theme.income
        case .neutral: Theme.brand
        case .warning: Theme.warning
        }
    }
}

public extension BudgetStatus.Level {
    var color: Color {
        switch self {
        case .onTrack: Theme.brand
        case .nearLimit: Theme.warning
        case .over: Theme.expense
        }
    }
}
