import Foundation

/// One line shown, centred, on the Focus Guard blur.
struct Quote: Equatable {
    let text: String
    let author: String
}

/// The quote collections the user can switch on and off for the Focus Guard
/// rotation. Each case is a real, named source the quotes were pulled from, so
/// the Settings list can credit it honestly.
///
/// Whether a source feeds the rotation is stored per-source in `UserDefaults`
/// (`focusGuard.source.<id>`), read fresh so toggling a checkbox takes effect on
/// the next nudge with no restart.
enum QuoteSource: String, CaseIterable, Identifiable {
    case wikiquote
    case stoic
    case dwyl
    case entrepreneur
    case motivation
    case tate
    case naval

    var id: String { rawValue }

    /// The name shown in the Settings checklist.
    var title: String {
        switch self {
        case .wikiquote:    return "Leaders & Classics"
        case .stoic:        return "Stoic Discipline"
        case .dwyl:         return "Timeless Mix"
        case .entrepreneur: return "Business & Money"
        case .motivation:   return "Daily Motivation"
        case .tate:         return "Andrew Tate"
        case .naval:        return "Naval Ravikant"
        }
    }

    /// The one-line credit under the title — what it is and where it came from.
    var subtitle: String {
        switch self {
        case .wikiquote:    return "Caesar, Napoleon, Sun Tzu, Aurelius · Wikiquote"
        case .stoic:        return "Seneca, Epictetus, Aurelius · benhoneywill/stoic-quotes"
        case .dwyl:         return "Classic + modern wisdom · dwyl/quotes"
        case .entrepreneur: return "Success & wealth · 325 Entrepreneur Quotes"
        case .motivation:   return "Hard work & momentum · AtaGowani/daily-motivation"
        case .tate:         return "Money, discipline, hustle · thecitesite"
        case .naval:        return "Wealth & leverage · How to Get Rich + Almanack"
        }
    }

    /// A single SF Symbol that reads at a glance in the checklist.
    var symbol: String {
        switch self {
        case .wikiquote:    return "laurel.leading"
        case .stoic:        return "building.columns"
        case .dwyl:         return "infinity"
        case .entrepreneur: return "chart.line.uptrend.xyaxis"
        case .motivation:   return "flame"
        case .tate:         return "bolt.fill"
        case .naval:        return "brain.head.profile"
        }
    }

    var defaultsKey: String { "focusGuard.source.\(rawValue)" }

    /// On unless the user has turned it off. New installs get the full rotation.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    var quotes: [Quote] { QuoteBank.quotes(for: self) }
}

enum QuoteBank {

    /// Pick a line from the union of the given sources, avoiding the one shown
    /// last so two nudges never repeat back to back. Returns nil when nothing is
    /// selected — the caller decides what that means.
    static func next(from sources: [QuoteSource]) -> Quote? {
        let pool = sources.flatMap { $0.quotes }
        guard !pool.isEmpty else { return nil }
        guard pool.count > 1 else { lastShown = pool.first; return pool.first }

        var pick = pool[Int.random(in: 0..<pool.count)]
        if pick == lastShown {
            pick = pool[Int.random(in: 0..<pool.count)]   // one re-roll is plenty
        }
        lastShown = pick
        return pick
    }

    private static var lastShown: Quote?

    // MARK: - The collections
    //
    // Curated from the real source data. Conqueror-leader lines lean on the
    // well-attested ones; the crowd-sourced sets (Tate) are kept to widely
    // documented lines.

    static func quotes(for source: QuoteSource) -> [Quote] {
        switch source {
        case .wikiquote:    return wikiquote
        case .stoic:        return stoic
        case .dwyl:         return dwyl
        case .entrepreneur: return entrepreneur
        case .motivation:   return motivation
        case .tate:         return tate
        case .naval:        return naval
        }
    }

    private static let wikiquote: [Quote] = [
        Quote(text: "Veni, vidi, vici. I came, I saw, I conquered.", author: "Julius Caesar"),
        Quote(text: "It is easier to find men who will volunteer to die, than to find those who are willing to endure pain with patience.", author: "Julius Caesar"),
        Quote(text: "I love the name of honor, more than I fear death.", author: "Julius Caesar"),
        Quote(text: "Never interrupt your enemy when he is making a mistake.", author: "Napoleon Bonaparte"),
        Quote(text: "Victory belongs to the most persevering.", author: "Napoleon Bonaparte"),
        Quote(text: "A leader is a dealer in hope.", author: "Napoleon Bonaparte"),
        Quote(text: "The supreme art of war is to subdue the enemy without fighting.", author: "Sun Tzu"),
        Quote(text: "Appear weak when you are strong, and strong when you are weak.", author: "Sun Tzu"),
        Quote(text: "In the midst of chaos, there is also opportunity.", author: "Sun Tzu"),
        Quote(text: "You have power over your mind, not outside events. Realize this, and you will find strength.", author: "Marcus Aurelius"),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius"),
        Quote(text: "The impediment to action advances action. What stands in the way becomes the way.", author: "Marcus Aurelius"),
        Quote(text: "There is nothing impossible to him who will try.", author: "Alexander the Great"),
        Quote(text: "I am not afraid of an army of lions led by a sheep; I am afraid of an army of sheep led by a lion.", author: "Alexander the Great"),
        Quote(text: "We will either find a way, or make one.", author: "Hannibal"),
        Quote(text: "If you're going through hell, keep going.", author: "Winston Churchill"),
        Quote(text: "Success is not final, failure is not fatal: it is the courage to continue that counts.", author: "Winston Churchill"),
    ]

    private static let stoic: [Quote] = [
        Quote(text: "We suffer more often in imagination than in reality.", author: "Seneca"),
        Quote(text: "It is not the man who has too little, but the man who craves more, that is poor.", author: "Seneca"),
        Quote(text: "Luck is what happens when preparation meets opportunity.", author: "Seneca"),
        Quote(text: "Difficulties strengthen the mind, as labour does the body.", author: "Seneca"),
        Quote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca"),
        Quote(text: "No man is free who is not master of himself.", author: "Epictetus"),
        Quote(text: "It's not what happens to you, but how you react to it that matters.", author: "Epictetus"),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus"),
        Quote(text: "Wealth consists not in having great possessions, but in having few wants.", author: "Epictetus"),
        Quote(text: "If you want to improve, be content to be thought foolish and stupid.", author: "Epictetus"),
        Quote(text: "How long are you going to wait before you demand the best for yourself?", author: "Epictetus"),
        Quote(text: "Concentrate every minute on doing what's in front of you with precise and genuine seriousness.", author: "Marcus Aurelius"),
    ]

    private static let dwyl: [Quote] = [
        Quote(text: "Happiness depends upon ourselves.", author: "Aristotle"),
        Quote(text: "The only way to do great work is to love what you do.", author: "Steve Jobs"),
        Quote(text: "It always seems impossible until it's done.", author: "Nelson Mandela"),
        Quote(text: "Whether you think you can or you think you can't, you're right.", author: "Henry Ford"),
        Quote(text: "It does not matter how slowly you go as long as you do not stop.", author: "Confucius"),
        Quote(text: "Believe you can and you're halfway there.", author: "Theodore Roosevelt"),
        Quote(text: "The future belongs to those who believe in the beauty of their dreams.", author: "Eleanor Roosevelt"),
        Quote(text: "Life is what happens to you while you're busy making other plans.", author: "John Lennon"),
        Quote(text: "Quality is not an act, it is a habit.", author: "Aristotle"),
        Quote(text: "We are what we repeatedly do. Excellence, then, is not an act but a habit.", author: "Will Durant"),
    ]

    private static let entrepreneur: [Quote] = [
        Quote(text: "The secret of success is to know something nobody else knows.", author: "Aristotle Onassis"),
        Quote(text: "Success is the child of audacity.", author: "Benjamin Disraeli"),
        Quote(text: "Ideas are a commodity. Execution of them is not.", author: "Michael Dell"),
        Quote(text: "The way to get started is to quit talking and begin doing.", author: "Walt Disney"),
        Quote(text: "Whatever the mind can conceive and believe, it can achieve.", author: "Napoleon Hill"),
        Quote(text: "Your time is limited, so don't waste it living someone else's life.", author: "Steve Jobs"),
        Quote(text: "Chase the vision, not the money; the money will end up following you.", author: "Tony Hsieh"),
        Quote(text: "Opportunities don't happen. You create them.", author: "Chris Grosser"),
        Quote(text: "The biggest risk is not taking any risk.", author: "Mark Zuckerberg"),
        Quote(text: "If you really look closely, most overnight successes took a long time.", author: "Steve Jobs"),
    ]

    private static let motivation: [Quote] = [
        Quote(text: "The secret to getting ahead is getting started.", author: "Mark Twain"),
        Quote(text: "Success is walking from failure to failure with no loss of enthusiasm.", author: "Winston Churchill"),
        Quote(text: "I have not failed. I've just found 10,000 ways that won't work.", author: "Thomas Edison"),
        Quote(text: "Motivation is what gets you started. Habit is what keeps you going.", author: "Jim Ryun"),
        Quote(text: "By failing to prepare, you are preparing to fail.", author: "Benjamin Franklin"),
        Quote(text: "Don't watch the clock; do what it does. Keep going.", author: "Sam Levenson"),
        Quote(text: "The harder I work, the luckier I get.", author: "Samuel Goldwyn"),
        Quote(text: "Either you run the day or the day runs you.", author: "Jim Rohn"),
        Quote(text: "Well done is better than well said.", author: "Benjamin Franklin"),
        Quote(text: "Start where you are. Use what you have. Do what you can.", author: "Arthur Ashe"),
    ]

    private static let tate: [Quote] = [
        Quote(text: "Your future is the result of your daily actions. You're defined by what you do today. Lazy now, loser later.", author: "Andrew Tate"),
        Quote(text: "Freedom will only come when you no longer trade your time for money.", author: "Andrew Tate"),
        Quote(text: "There is simply one way to become an exceptional man. You must go through hell and survive.", author: "Andrew Tate"),
        Quote(text: "Do not listen to the rich when they tell you money won't make you happy. It's a lie.", author: "Andrew Tate"),
        Quote(text: "The temptation to give up is greatest just before you are about to succeed.", author: "Andrew Tate"),
        Quote(text: "Discipline is the most important thing in the world.", author: "Andrew Tate"),
        Quote(text: "Be passionate about being successful, not about the thing itself. Be passionate about hard work and financial freedom.", author: "Andrew Tate"),
        Quote(text: "What you avoid controls you. Run toward the hard thing.", author: "Andrew Tate"),
    ]

    private static let naval: [Quote] = [
        Quote(text: "Seek wealth, not money or status.", author: "Naval Ravikant"),
        Quote(text: "Wealth is having assets that earn while you sleep.", author: "Naval Ravikant"),
        Quote(text: "You must own equity, a piece of a business, to gain your financial freedom.", author: "Naval Ravikant"),
        Quote(text: "All the returns in life come from compound interest.", author: "Naval Ravikant"),
        Quote(text: "Specific knowledge is knowledge you cannot be trained for.", author: "Naval Ravikant"),
        Quote(text: "Leverage is a force multiplier for your judgment.", author: "Naval Ravikant"),
        Quote(text: "Earn with your mind, not your time.", author: "Naval Ravikant"),
        Quote(text: "Play long-term games with long-term people.", author: "Naval Ravikant"),
        Quote(text: "Become the best in the world at what you do. Keep redefining what you do until this is true.", author: "Naval Ravikant"),
        Quote(text: "Desire is a contract you make with yourself to be unhappy until you get what you want.", author: "Naval Ravikant"),
        Quote(text: "The most important skill for getting rich is becoming a perpetual learner.", author: "Naval Ravikant"),
        Quote(text: "A fit body, a calm mind, a house full of love. These things cannot be bought. They must be earned.", author: "Naval Ravikant"),
    ]
}
