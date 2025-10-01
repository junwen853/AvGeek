import SwiftUI
import Foundation
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

// ======================================================
// MARK: - Models
// ======================================================

enum ProductionStatus: String, Codable, CaseIterable, Identifiable {
    case inProduction = "In Production"
    case discontinued = "Discontinued"
    var id: String { rawValue }
    var color: Color { self == .inProduction ? .green : .red }
}

enum AircraftCategory: String, Codable, CaseIterable, Identifiable {
    case narrowBody        = "Narrow-body"
    case wideBody          = "Wide-body"
    case regionalJet       = "Regional Jet"
    case regionalTurboprop = "Regional Turboprop"
    case businessJet       = "Business Jet"
    case freighter         = "Freighter"
    case supersonic        = "Supersonic"
    case other             = "Other"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .freighter: return "shippingbox"
        case .businessJet: return "briefcase"
        case .supersonic: return "bolt"
        default: return "airplane"
        }
    }

    // 宽松解码，兼容不同写法（防止 JSON 里"Regional Turboprop"等变体）
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let original = (try? c.decode(String.self)) ?? ""
        let s = original.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()

        if s.contains("narrow") { self = .narrowBody; return }
        if s.contains("wide") { self = .wideBody; return }
        if s.contains("regional") && s.contains("turbo") { self = .regionalTurboprop; return }
        if s.contains("regional") && s.contains("jet") { self = .regionalJet; return }
        if s.contains("business") || s.contains("biz") { self = .businessJet; return }
        if s.contains("freight") || s.contains("cargo") { self = .freighter; return }
        if s.contains("supersonic") { self = .supersonic; return }
        self = .other
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

struct Aircraft: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var manufacturer: String
    var iata: String?
    var icao: String?
    var category: AircraftCategory
    var status: ProductionStatus
    var rangeKM: Int?
    var cruiseSpeedKMH: Int?
    var typicalSeating: String?
    var firstFlightYear: Int?
    var productionStart: Int?
    var productionEnd: Int?
    var intro: String
    var fuelBurnKgPerHour: Double?  // average block fuel burn (kg/h)
    var imageNames: [String] = []
}

struct Airport: Identifiable, Codable, Hashable {
    var id: String { iata }
    var iata: String
    var name: String
    var city: String
    var country: String
    var latitude: Double
    var longitude: Double
}

enum CabinClass: String, Codable, CaseIterable, Identifiable {
    case economy = "Economy"
    case premiumEconomy = "Premium Economy"
    case business = "Business"
    case first = "First"
    var id: String { rawValue }
}

struct FlightLog: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var aircraftID: String
    var originIATA: String
    var destinationIATA: String
    var distanceKM: Double
    var note: String?
    var cabin: CabinClass? = nil
}

// ======================================================
// MARK: - Store
// ======================================================

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var aircrafts: [Aircraft] = []
    @Published var airports: [Airport] = []
    @Published var flights: [FlightLog] = [] {
        didSet {
            saveFlights()
            checkNewBadges()
        }
    }
    @Published var favorites: Set<String> = [] { didSet { saveFavorites() } }
    @Published var newBadge: RewardBadge? // recently earned badge for toast
    @Published var badgeQueue: [RewardBadge] = [] // queue of badges to show
    @Published var currentBadgeShowsFireworks: Bool = false
    private var lastEarnedTitles: Set<String> = []
    private var displayedBadgeTitles: Set<String> = []
    private let earnedKey = "earned_badge_titles"
    private let displayedKey = "displayed_badge_titles"
    private var isRestoringState = true

    private init() {
        loadAircrafts()
        loadAirports()
        loadFavorites()
        if let saved = UserDefaults.standard.array(forKey: earnedKey) as? [String] {
            lastEarnedTitles = Set(saved)
        }
        if let shown = UserDefaults.standard.array(forKey: displayedKey) as? [String] {
            displayedBadgeTitles = Set(shown)
        }
        let earnedNow = computeBadges(store: self).filter { $0.achieved }.map { $0.title }
        lastEarnedTitles.formUnion(earnedNow)
        UserDefaults.standard.set(Array(lastEarnedTitles), forKey: earnedKey)

        loadFlights()
        isRestoringState = false
        checkNewBadges()
    }

    // Bundle JSON loaders
    private func loadAircrafts() {
        guard let url = Bundle.main.url(forResource: "aircraft_db", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Aircraft].self, from: data)
        else { return }
        aircrafts = list.sorted { $0.name < $1.name }
    }

    private func loadAirports() {
        guard let url = Bundle.main.url(forResource: "airports_db", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Airport].self, from: data)
        else { return }
        airports = list.sorted { $0.iata < $1.iata }
    }

    // Flight logs persistence
    private var flightsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("flight_logs.json")
    }
    private func loadFlights() {
        if let data = try? Data(contentsOf: flightsURL),
           let list = try? JSONDecoder().decode([FlightLog].self, from: data) {
            flights = list
        }
    }
    private func saveFlights() {
        if let data = try? JSONEncoder().encode(flights) {
            try? data.write(to: flightsURL, options: [.atomic])
        }
    }

    // Favorites persistence
    private let favKey = "favorites_aircraft_ids"
    private func loadFavorites() {
        if let arr = UserDefaults.standard.array(forKey: favKey) as? [String] {
            favorites = Set(arr)
        }
    }
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favKey)
    }

    private func checkNewBadges() {
        guard !isRestoringState else { return }
        let earned = computeBadges(store: self).filter { $0.achieved }
        let currentTitles = Set(earned.map { $0.title })
        let newOnes = currentTitles.subtracting(lastEarnedTitles)
        
        if !newOnes.isEmpty {
            // Get all new badges
            let newBadges = earned.filter { newOnes.contains($0.title) }
            
            // Persist new state first
            lastEarnedTitles.formUnion(newOnes)
            UserDefaults.standard.set(Array(lastEarnedTitles), forKey: earnedKey)
            
            let unseenBadges = newBadges.filter { !displayedBadgeTitles.contains($0.title) }
            guard !unseenBadges.isEmpty else { return }
            badgeQueue.append(contentsOf: unseenBadges)
            showNextBadge(playFireworks: true)
        }
    }
    
    private func showNextBadge(playFireworks: Bool = false) {
        guard !badgeQueue.isEmpty else { return }
        let badge = badgeQueue.removeFirst()
        currentBadgeShowsFireworks = playFireworks
        displayedBadgeTitles.insert(badge.title)
        UserDefaults.standard.set(Array(displayedBadgeTitles), forKey: displayedKey)

        // Haptic feedback
#if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
#endif
        
        // Present celebration
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            self.newBadge = badge
        }
    }
    
    func dismissCurrentBadge() {
        guard let current = newBadge else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            self.newBadge = nil
        }

        // Show next badge after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.badgeQueue.isEmpty {
                self.showNextBadge(playFireworks: false)
            }
        }
    }

    // Lookups
    func airport(by code: String) -> Airport? {
        airports.first { $0.iata.caseInsensitiveCompare(code) == .orderedSame }
    }
    func aircraft(by id: String) -> Aircraft? {
        aircrafts.first { $0.id == id }
    }

    // Stats
    var totalDistanceKM: Double { flights.map(\.distanceKM).reduce(0, +) }
    var totalFlights: Int { flights.count }

    func distanceByManufacturer() -> [(String, Double)] {
        var dict: [String: Double] = [:]
        for f in flights {
            if let m = aircraft(by: f.aircraftID)?.manufacturer {
                dict[m, default: 0] += f.distanceKM
            }
        }
        return dict.sorted { $0.value > $1.value }
    }

    func distanceByAircraft() -> [(Aircraft, Double)] {
        var dict: [String: Double] = [:]
        for f in flights { dict[f.aircraftID, default: 0] += f.distanceKM }
        return dict.compactMap { (id, km) in
            guard let ac = aircraft(by: id) else { return nil }
            return (ac, km)
        }.sorted { $0.1 > $1.1 }
    }

    // Extended Stats (airports/records)
    /// Visits per airport (count of appearances as origin or destination)
    func visitsByAirport() -> [(String, Int)] {
        var count: [String: Int] = [:]
        for f in flights {
            count[f.originIATA, default: 0] += 1
            count[f.destinationIATA, default: 0] += 1
        }
        return count.sorted { $0.value > $1.value }
    }

    /// Distance aggregated by airport (sum of km for flights touching the airport)
    func distanceByAirport() -> [(String, Double)] {
        var kmMap: [String: Double] = [:]
        for f in flights {
            kmMap[f.originIATA, default: 0] += f.distanceKM
            kmMap[f.destinationIATA, default: 0] += f.distanceKM
        }
        return kmMap.sorted { $0.value > $1.value }
    }

    /// Top N airports by visits
    func topAirports(limit: Int = 5) -> [(String, Int)] {
        Array(visitsByAirport().prefix(limit))
    }

    /// Longest single flight distance (km)
    func maxSingleFlightKM() -> Double { flights.map(\.distanceKM).max() ?? 0 }

    /// Whether user has any premium-cabin (Business/First) flights
    func hasPremiumCabinFlight() -> Bool {
        flights.contains { $0.cabin == .business || $0.cabin == .first }
    }

    // Estimated totals (offline, derived from logs)
    func totalEstimatedFuelKG() -> Double {
        flights.reduce(0) { acc, f in
            guard let ac = aircraft(by: f.aircraftID) else { return acc }
            let speed: Double = {
                switch ac.category {
                case .regionalTurboprop: return 500
                case .regionalJet: return 780
                default: return 840
                }
            }()
            let hours = f.distanceKM / speed
            let burn = ac.fuelBurnKgPerHour ?? 2600 // fallback avg jet
            return acc + burn * hours
        }
    }
    func totalEstimatedCO2KG() -> Double { totalEstimatedFuelKG() * 3.16 }
}

// Export / Import（完整实现）
extension DataStore {
    func exportLogs() -> URL? {
        let ts = Int(Date().timeIntervalSince1970)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("avgeek_logs_\(ts).json")
        do {
            let data = try JSONEncoder().encode(flights)
            try data.write(to: outURL, options: [.atomic])
            return outURL
        } catch {
            print("Export failed:", error)
            return nil
        }
    }

    func importLogs(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let incoming = try JSONDecoder().decode([FlightLog].self, from: data)
        var seen = Set(flights.map { $0.id })
        var merged = flights
        for item in incoming where !seen.contains(item.id) {
            merged.append(item)
            seen.insert(item.id)
        }
        flights = merged
    }
}

// ======================================================
// MARK: - App (System TabView root)
// ======================================================

@main
struct AvGeekApp: App {
    @StateObject private var store = DataStore.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false // 首次安装显示欢迎引导

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                SystemTabRootView()                 // ✅ 系统原生 TabView（iOS 26 自动 Liquid Glass）
                    .environmentObject(store)
                    .tint(.blue)                    // 全局蓝色
            } else {
                OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                    .environmentObject(store)
                    .tint(.blue)
            }
        }
    }
}

// ======================================================
// MARK: - System Tab Root (只负责装载页面；其它页面不动)
// ======================================================

enum AppTab: String, CaseIterable, Identifiable {
    case fleet, route, logbook, stats, about
    var id: String { rawValue }
}

struct SystemTabRootView: View {
    @EnvironmentObject var store: DataStore
    @State private var tab: AppTab = .fleet
    @State private var compareSheet = false

    var body: some View {
        TabView(selection: $tab) {
            AircraftListView()
                .environmentObject(store)
                .tabItem { Label("Fleet", systemImage: "airplane") }
                .tag(AppTab.fleet)

            RouteSimView()
                .environmentObject(store)
                .tabItem { Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                .tag(AppTab.route)

            FlightListView()
                .environmentObject(store)
                .tabItem { Label("Logbook", systemImage: "note.text") }
                .tag(AppTab.logbook)

            StatsView()
                .environmentObject(store)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.stats)

            AboutView(compareSheet: $compareSheet)
                .environmentObject(store)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(AppTab.about)
        }
        // iOS 26 自动 Liquid Glass；确保可见
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .sheet(isPresented: $compareSheet) {
            CompareView().environmentObject(store).presentationDetents([.large])
        }
        .overlay {
            if let badge = store.newBadge {
                BadgeCelebrationView(
                    badge: badge,
                    hasMore: !store.badgeQueue.isEmpty,
                    showFireworks: store.currentBadgeShowsFireworks,
                    onDismiss: { store.dismissCurrentBadge() }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(20)
            }
        }
    }
}

// ======================================================
// MARK: - Onboarding（保持你先前的结构）
// ======================================================

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool

    @State private var page: Int = 0

    private let pages: [(title: String, subtitle: String, systemImage: String, top: Color, bottom: Color)] = [
        ("AviationGeek",
         "Your offline companion for aircraft browsing, route simulation and personal flight logging.",
         "airplane.circle.fill", .blue, .indigo),
        ("Browse Aircraft",
         "Search by name, manufacturer, status, and category. All data lives on-device—no internet required.",
         "square.grid.2x2.fill", .teal, .blue),
        ("Simulate Routes",
         "Pick origin & destination to get great-circle distance, estimated time, and range check for your aircraft.",
         "point.topleft.down.curvedto.point.bottomright.up", .mint, .green),
        ("Logbook & Stats",
         "Save flights with date and notes, then see your totals by aircraft and manufacturer.",
         "chart.bar.fill", .orange, .red),
        ("Earn Rewards",
         "Hit distance milestones (10k, 50k, 100k+ km) and flight counts to unlock badges.",
         "rosette", .purple, .pink)
    ]

    var body: some View {
        ZStack {
            // Background of current page to ensure full-bleed color even during transition
            LinearGradient(colors: [pages[page].top, pages[page].bottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                    let delta = CGFloat(idx - page)
                    OnboardingPage(
                        title: p.title,
                        subtitle: p.subtitle,
                        systemImage: p.systemImage,
                        top: p.top,
                        bottom: p.bottom
                    )
                    .rotation3DEffect(.degrees(Double(delta) * 8), axis: (x: 0, y: 1, z: 0))
                    .scaleEffect(1 - abs(delta) * 0.05)
                    .opacity(1 - abs(delta) * 0.15)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button("Skip") {
                    hasSeenOnboarding = true
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut) { page += 1 }
                } else {
                    hasSeenOnboarding = true
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

// Animated soft bubbles for onboarding background
struct MovingBubbles: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = 8
                for i in 0..<count {
                    let speed = 0.25 + 0.08 * Double(i % 3)
                    let r: CGFloat = 90 + CGFloat((i * 13) % 40)
                    let x = size.width  * 0.5 + CGFloat(cos(t * speed + Double(i))) * size.width  * 0.35
                    let y = size.height * 0.5 + CGFloat(sin(t * (speed * 0.9) + Double(i))) * size.height * 0.35
                    var rect = CGRect(x: x - r/2, y: y - r/2, width: r, height: r)

                    ctx.addFilter(.blur(radius: 24))
                    let alpha: CGFloat = 0.10 + CGFloat((i % 3)) * 0.04
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))

                    // subtle highlight
                    rect = rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha * 0.6)))
                }
            }
        }
        .ignoresSafeArea()
        .blendMode(.plusLighter)
        .opacity(0.28)
    }
}

struct OnboardingPage: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let top: Color
    let bottom: Color

    @State private var iconScale: CGFloat = 0.92
    @State private var iconFloat: CGFloat = 0

    var body: some View {
        ZStack {
            // Full-bleed animated gradient background
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // Soft moving bubbles for depth (very subtle)
            MovingBubbles()
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                Spacer(minLength: 20)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 200, height: 200)
                        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)

                    Image(systemName: systemImage)
                        .font(.system(size: 96, weight: .bold))
#if compiler(>=5.9)
                        .symbolRenderingMode(.hierarchical)
#endif
                        .foregroundStyle(.primary)
                        .scaleEffect(iconScale)
                        .offset(y: iconFloat)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                                iconScale = 1.03
                            }
                            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                iconFloat = -8
                            }
                        }
                }

                Text(title)
                    .font(.system(.largeTitle, design: .rounded)).bold()
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .padding()
        }
    }
}

// ======================================================
// MARK: - Aircraft List & Detail（不改逻辑）
// ======================================================

struct AircraftListView: View {
    @EnvironmentObject var store: DataStore
    @State private var query = ""
    @State private var status: ProductionStatus? = nil
    @State private var category: AircraftCategory? = nil
    @State private var manufacturer: String = "All"
    @State private var showOnlyFavorites = false

    private var manufacturers: [String] {
        ["All"] + Array(Set(store.aircrafts.map(\.manufacturer))).sorted()
    }

    private var filtered: [Aircraft] {
        store.aircrafts.filter { ac in
            let matchText = query.isEmpty ||
                ac.name.localizedCaseInsensitiveContains(query) ||
                ac.manufacturer.localizedCaseInsensitiveContains(query) ||
                (ac.iata ?? "").localizedCaseInsensitiveContains(query) ||
                (ac.icao ?? "").localizedCaseInsensitiveContains(query)
            let matchStatus = (status == nil) || ac.status == status!
            let matchCat = (category == nil) || ac.category == category!
            let matchM = (manufacturer == "All") || ac.manufacturer == manufacturer
            let matchFav = !showOnlyFavorites || store.favorites.contains(ac.id)
            return matchText && matchStatus && matchCat && matchM && matchFav
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty || status != nil || category != nil || manufacturer != "All" || showOnlyFavorites {
                    Section {
                        HStack {
                            Text("Filtered: \(filtered.count)")
                            Spacer()
                            Button("Clear") {
                                query = ""; status = nil; category = nil; manufacturer = "All"; showOnlyFavorites = false
                            }.buttonStyle(.borderless)
                        }.font(.footnote)
                    }
                }

                ForEach(filtered) { ac in
                    NavigationLink {
                        AircraftDetailView(aircraft: ac)
                    } label: {
                        HStack {
                            aircraftThumbnail(for: ac)
                                .frame(width: 56, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ac.name).font(.headline)
                                HStack(spacing: 6) {
                                    Text(ac.manufacturer).font(.subheadline)
                                    Image(systemName: ac.category.icon).font(.subheadline).foregroundStyle(.secondary)
                                    Circle().fill(ac.status.color).frame(width: 8, height: 8)
                                    Text(ac.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if store.favorites.contains(ac.id) { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                        }
                    }
                    .contextMenu {
                        Button(store.favorites.contains(ac.id) ? "Remove Favorite" : "Add to Favorites") {
                            if store.favorites.contains(ac.id) { store.favorites.remove(ac.id) } else { store.favorites.insert(ac.id) }
                        }
                        Button("Compare…") { CompareSelection.shared.pick(ac) }
                    }
                }
            }
            .navigationTitle("Aircraft Library")
            .searchable(text: $query, placement: .navigationBarDrawer, prompt: "Search name/IATA/ICAO/Manufacturer")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Status", selection: Binding(get: { status }, set: { status = $0 })) {
                            Text("All").tag(ProductionStatus?.none)
                            ForEach(ProductionStatus.allCases) { Text($0.rawValue).tag(ProductionStatus?.some($0)) }
                        }
                        Picker("Category", selection: Binding(get: { category }, set: { category = $0 })) {
                            Text("All").tag(AircraftCategory?.none)
                            ForEach(AircraftCategory.allCases) { Text($0.rawValue).tag(AircraftCategory?.some($0)) }
                        }
                        Picker("Manufacturer", selection: $manufacturer) {
                            ForEach(manufacturers, id: \.self) { Text($0) }
                        }
                        Toggle("Favorites only", isOn: $showOnlyFavorites)
                    } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
        }
    }
}

struct AircraftDetailView: View {
    @EnvironmentObject var store: DataStore
    let aircraft: Aircraft
    @State private var showRoute = false

    var myKM: Double {
        store.flights.filter { $0.aircraftID == aircraft.id }.map(\.distanceKM).reduce(0,+)
    }

    var body: some View {
        List {
            if !aircraft.imageNames.isEmpty {
                TabView {
                    ForEach(aircraft.imageNames, id: \.self) { img in
                        Image(img).resizable().scaledToFill().frame(height: 220).clipped()
                    }
                }
                .frame(height: 220).tabViewStyle(.page)
            }

            Section("Overview") {
                infoRow("Name", aircraft.name)
                infoRow("Manufacturer", aircraft.manufacturer)
                infoRow("Category", aircraft.category.rawValue)
                if let i = aircraft.iata { infoRow("IATA", i) }
                if let i = aircraft.icao { infoRow("ICAO", i) }
                HStack {
                    Text("Status"); Spacer()
                    Label(aircraft.status.rawValue, systemImage: "circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(aircraft.status.color, .secondary)
                }
                if let s = aircraft.productionStart {
                    infoRow("Production", "\(s) – \(aircraft.productionEnd.map(String.init) ?? "present")")
                }
                if let y = aircraft.firstFlightYear { infoRow("First flight", "\(y)") }
            }

            Section("Performance") {
                if let r = aircraft.rangeKM { infoRow("Range", "\(r) km") }
                if let v = aircraft.cruiseSpeedKMH { infoRow("Cruise", "\(v) km/h") }
                if let s = aircraft.typicalSeating { infoRow("Seating", s) }
            }

            Section("Description") { Text(aircraft.intro) }

            Section("My stats") {
                HStack { Text("Distance on this type"); Spacer(); Text("\(Int(myKM)) km").bold() }
                Button(store.favorites.contains(aircraft.id) ? "Remove from Favorites" : "Add to Favorites") {
                    if store.favorites.contains(aircraft.id) { store.favorites.remove(aircraft.id) } else { store.favorites.insert(aircraft.id) }
                }
            }
        }
        .navigationTitle(aircraft.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showRoute = true } label: { Label("Simulate Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            }
        }
        .sheet(isPresented: $showRoute) { RouteSimView(prefilledAircraft: aircraft) }
    }

    @ViewBuilder private func infoRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

// ======================================================
// MARK: - Compare（保持）
// ======================================================

final class CompareSelection: ObservableObject {
    static let shared = CompareSelection()
    @Published var first: Aircraft?
    @Published var second: Aircraft?
    func pick(_ ac: Aircraft) {
        if first == nil { first = ac }
        else if second == nil && ac.id != first?.id { second = ac }
    }
    func clear() { first = nil; second = nil }
}

struct CompareView: View {
    @EnvironmentObject var store: DataStore
    @StateObject var sel = CompareSelection.shared
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack { AircraftCard(selection: $sel.first); AircraftCard(selection: $sel.second) }
                    .padding(.horizontal)
                if let a = sel.first, let b = sel.second {
                    List {
                        Section("Overview") {
                            compareRow("Name", a.name, b.name)
                            compareRow("Manufacturer", a.manufacturer, b.manufacturer)
                            compareRow("Category", a.category.rawValue, b.category.rawValue)
                            compareRow("Status", a.status.rawValue, b.status.rawValue)
                            compareRow("First Flight", a.firstFlightYear.map(String.init) ?? "—", b.firstFlightYear.map(String.init) ?? "—")
                            compareRow("Production", prodText(a), prodText(b))
                        }
                        Section("Performance") {
                            compareRow("Range (km)", a.rangeKM.map(String.init) ?? "—", b.rangeKM.map(String.init) ?? "—")
                            compareRow("Cruise (km/h)", a.cruiseSpeedKMH.map(String.init) ?? "—", b.cruiseSpeedKMH.map(String.init) ?? "—")
                            compareRow("Seating", a.typicalSeating ?? "—", b.typicalSeating ?? "—")
                            compareRow("Fuel burn (kg/h)",
                                       a.fuelBurnKgPerHour.map { String(Int($0)) } ?? "—",
                                       b.fuelBurnKgPerHour.map { String(Int($0)) } ?? "—")
                        }
                        Section("My stats") {
                            let aMy = store.flights.filter { $0.aircraftID == a.id }.map(\.distanceKM).reduce(0,+)
                            let bMy = store.flights.filter { $0.aircraftID == b.id }.map(\.distanceKM).reduce(0,+)
                            compareRow("My distance (km)", String(Int(aMy)), String(Int(bMy)))
                        }
                    }
                } else {
                    Text("Pick two aircraft from the list (long-press → Compare…)").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .navigationTitle("Compare")
            .toolbar { Button("Clear") { sel.clear() } }
        }
    }
    func prodText(_ x: Aircraft) -> String {
        if let s = x.productionStart { return "\(s) – \(x.productionEnd.map(String.init) ?? "present")" }
        return "—"
    }
    @ViewBuilder func compareRow(_ title: String, _ a: String, _ b: String) -> some View {
        HStack {
            Text(title); Spacer()
            Text(a).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(.secondary)
            Divider().frame(height: 16)
            Text(b).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(.secondary)
        }.font(.subheadline)
    }
}

struct AircraftCard: View {
    @EnvironmentObject var store: DataStore
    @Binding var selection: Aircraft?
    @State private var showPicker = false
    var body: some View {
        VStack {
            if let ac = selection {
                Text(ac.name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                Text(ac.manufacturer).font(.caption).foregroundStyle(.secondary)
                Button("Change") { showPicker = true }
            } else {
                Button { showPicker = true } label: {
                    VStack { Image(systemName: "plus.circle").font(.largeTitle); Text("Select").font(.caption) }
                }
            }
        }
        .frame(maxWidth: .infinity).padding().background(.ultraThinMaterial).cornerRadius(12)
        .sheet(isPresented: $showPicker) { AircraftPicker(selection: $selection) }
    }
}

struct AircraftPicker: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @Binding var selection: Aircraft?
    @State private var query = ""
    var filtered: [Aircraft] {
        if query.isEmpty { return store.aircrafts }
        return store.aircrafts.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.manufacturer.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { ac in
                Button { selection = ac; dismiss() } label: { Text(ac.name) }
            }
            .navigationTitle("Pick Aircraft")
            .searchable(text: $query)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
        }
    }
}

// ======================================================
// MARK: - Route Simulator（保持）
// ======================================================

struct RouteSimView: View {
    @EnvironmentObject var store: DataStore
    var prefilledAircraft: Aircraft? = nil

    @State private var origin: Airport?
    @State private var destination: Airport?
    @State private var selectedAircraftID: String? = nil
    @State private var showOriginPicker = false
    @State private var showDestPicker = false
    @State private var showSavedToast = false
    @State private var date = Date()
    @State private var note = ""
    @State private var cabin: CabinClass? = nil

    init(prefilledAircraft: Aircraft? = nil) {
        self.prefilledAircraft = prefilledAircraft
        _selectedAircraftID = State(initialValue: prefilledAircraft?.id)
    }

    var selectedAircraft: Aircraft? { selectedAircraftID.flatMap { store.aircraft(by: $0) } }

    var computedKM: Double? {
        guard let o = origin, let d = destination else { return nil }
        return haversineKM(lat1: o.latitude, lon1: o.longitude, lat2: d.latitude, lon2: d.longitude)
    }

    var estimatedMinutes: Int? {
        guard let km = computedKM else { return nil }
        let speed = selectedAircraft?.cruiseSpeedKMH ?? {
            switch selectedAircraft?.category {
            case .regionalTurboprop?: return 500
            case .regionalJet?: return 780
            default: return 840
            }
        }()
        let hours = km / Double(speed)
        return Int((hours * 60).rounded())
    }

    var estimatedHours: Double? {
        guard let min = estimatedMinutes else { return nil }
        return Double(min) / 60.0
    }
    var estimatedFuelKG: Double? {
        guard let h = estimatedHours, let burn = selectedAircraft?.fuelBurnKgPerHour else { return nil }
        return burn * h
    }
    var estimatedCO2KG: Double? {
        guard let fuel = estimatedFuelKG else { return nil }
        return fuel * 3.16 // ~3.16 kg CO₂ per kg Jet A
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Airports") {
                    Button { showOriginPicker = true } label: { row("Origin", value: origin?.iata ?? "Select") }
                    Button { showDestPicker = true } label: { row("Destination", value: destination?.iata ?? "Select") }
                }
                Section("Aircraft") {
                    Picker("Type", selection: $selectedAircraftID) {
                        Text("Select").tag(Optional<String>.none)
                        ForEach(store.aircrafts) { a in Text(a.name).tag(Optional(a.id)) } // String? tag
                    }
                }
                Section("Result") {
                    if let km = computedKM {
                        HStack { Text("Distance"); Spacer(); Text("\(Int(km)) km  (\(Int(km * 0.539957)) nm)").bold() }
                        if let min = estimatedMinutes {
                            HStack { Text("Estimated time"); Spacer(); Text("\(min/60)h \(min%60)m") }
                        }
                        if let ac = selectedAircraft, let r = ac.rangeKM {
                            let ok = km <= Double(r)
                            HStack { Text("Within range?"); Spacer(); Text(ok ? "YES" : "NO").bold().foregroundStyle(ok ? .green : .red) }
                        }
                    } else {
                        Text("Pick airports to compute great-circle distance.").foregroundStyle(.secondary)
                    }
                    if let fuel = estimatedFuelKG {
                        let t = fuel / 1000.0
                        HStack { Text("Estimated fuel"); Spacer(); Text(String(format: "%.2f t", t)) }
                    }
                    if let co2 = estimatedCO2KG {
                        let t = co2 / 1000.0
                        HStack { Text("Estimated CO₂"); Spacer(); Text(String(format: "%.2f t", t)) }
                    }
                }
                Section("Cabin") {
                    Picker("Cabin", selection: Binding(get: { cabin }, set: { cabin = $0 })) {
                        Text("Not set").tag(CabinClass?.none)
                        ForEach(CabinClass.allCases) { c in
                            Text(c.rawValue).tag(CabinClass?.some(c))
                        }
                    }
                }
                Section("Save to log") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                    Button {
                        if let km = computedKM, let ac = selectedAircraft, let o = origin, let d = destination {
                            let log = FlightLog(date: date, aircraftID: ac.id, originIATA: o.iata, destinationIATA: d.iata, distanceKM: km, note: note.isEmpty ? nil : note, cabin: cabin)
                            store.flights.append(log); showSavedToast = true
                        }
                    } label: { Label("Add as flight log", systemImage: "plus") }
                    .disabled(!(computedKM != nil && selectedAircraft != nil && origin != nil && destination != nil))
                }
            }
            .navigationTitle("Route Simulator")
            .sheet(isPresented: $showOriginPicker) { AirportPickerView(selection: $origin).presentationDetents([.large]) }
            .sheet(isPresented: $showDestPicker) { AirportPickerView(selection: $destination).presentationDetents([.large]) }
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    Text("Saved to log ✓").padding(10).background(.ultraThinMaterial).cornerRadius(12).padding()
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now()+1.2) { withAnimation { showSavedToast = false } } }
                }
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

// 选择机场
struct AirportPickerView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @Binding var selection: Airport?
    @State private var query = ""

    var filtered: [Airport] {
        if query.isEmpty { return store.airports }
        let q = query.lowercased()
        return store.airports.filter {
            $0.iata.lowercased().contains(q)
            || $0.city.lowercased().contains(q)
            || $0.name.lowercased().contains(q)
            || $0.country.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { ap in
                Button { selection = ap; dismiss() } label: {
                    HStack {
                        Text(ap.iata).font(.headline).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(ap.name)
                            Text("\(ap.city), \(ap.country)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.3f, %.3f", ap.latitude, ap.longitude)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Select Airport")
            .searchable(text: $query, prompt: "IATA / city / name")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }
}


// ======================================================
// MARK: - Logbook / Stats / About（保持）
// ======================================================

struct FlightListView: View {
    @EnvironmentObject var store: DataStore
    @State private var newestFirst = true
    @State private var importing = false

    private var list: [FlightLog] {
        store.flights.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.flights.isEmpty {
                    ContentUnavailableView("No flights yet", systemImage: "airplane.departure", description: Text("Use Route to simulate a flight, or add from an aircraft page."))
                } else {
                    ForEach(list) { f in
                        FlightRow(f: f)
                    }
                    .onDelete { idx in
                        let ids = idx.map { list[$0].id }
                        store.flights.removeAll { ids.contains($0.id) }
                    }
                }
            }
            .navigationTitle("Logbook")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Toggle(isOn: $newestFirst) { Text("Newest first") } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let url = store.exportLogs() {
                            ShareLink(item: url) { Label("Export logs (JSON)", systemImage: "square.and.arrow.up") }
                        }
                        Button { importing = true } label: { Label("Import logs (JSON)", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "square.and.arrow.up.on.square") }
                }
                ToolbarItem(placement: .bottomBar) { Text("Total: \(Int(store.totalDistanceKM)) km") }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { res in
                do { try store.importLogs(from: try res.get()) } catch { print("Import failed:", error) }
            }
        }
    }

    struct FlightRow: View {
        @EnvironmentObject var store: DataStore
        var f: FlightLog
        private static let df: DateFormatter = { let d = DateFormatter(); d.dateStyle = .medium; return d }()
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Self.df.string(from: f.date)).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let ac = store.aircraft(by: f.aircraftID) { Text(ac.name).font(.subheadline).foregroundStyle(.secondary) }
                }
                HStack {
                    Text(f.originIATA).font(.headline)
                    Image(systemName: "airplane")
                    Text(f.destinationIATA).font(.headline)
                    Spacer()
                    Text("\(Int(f.distanceKM)) km").foregroundStyle(.secondary)
                    cabinBadge(f.cabin)
                }
                if let n = f.note, !n.isEmpty { Text(n).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}



struct StatsView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        NavigationStack {
            List {
                Section("Badges") {
                    let earned = computeBadges(store: store).filter { $0.achieved }
                    if earned.isEmpty {
                        Text("No badges yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(earned) { b in
                            HStack(spacing: 10) {
                                Image(systemName: b.icon)
                                Text(b.title)
                                Spacer()
                                Text(b.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Overview") {
                    HStack { Text("Flights"); Spacer(); Text("\(store.totalFlights)") }
                    HStack { Text("Distance"); Spacer(); Text("\(Int(store.totalDistanceKM)) km").bold() }
                }
                Section("By manufacturer (km)") {
                    ForEach(store.distanceByManufacturer(), id: \.0) { (m, km) in
                        HStack { Text(m); Spacer(); Text("\(Int(km))") }
                    }
                }
                Section("By aircraft (km)") {
                    ForEach(store.distanceByAircraft(), id: \.0.id) { (ac, km) in
                        HStack { Text(ac.name); Spacer(); Text("\(Int(km))") }
                    }
                }
                Section("By airport (visits)") {
                    let top = Array(store.visitsByAirport().prefix(10))
                    if top.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
                    else {
                        ForEach(top, id: \.0) { (code, times) in
                            HStack { Text(code); Spacer(); Text("\(times)") }
                        }
                    }
                }

                Section("By airport (km)") {
                    let top = Array(store.distanceByAirport().prefix(10))
                    if top.isEmpty { Text("No data yet").foregroundStyle(.secondary) }
                    else {
                        ForEach(top, id: \.0) { (code, km) in
                            HStack { Text(code); Spacer(); Text("\(Int(km))") }
                        }
                    }
                }
                Section("Top 3 aircraft (my km)") {
                    let top3 = Array(store.distanceByAircraft().prefix(3))
                    if top3.isEmpty {
                        Text("No data yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(top3, id: \.0.id) { (ac, km) in
                            HStack { Text(ac.name); Spacer(); Text("\(Int(km)) km") }
                        }
                    }
                }
                Section("CO₂ summary") {
                    let co2kg = store.totalEstimatedCO2KG()
                    let t = co2kg / 1000.0
                    HStack { Text("Estimated CO₂"); Spacer(); Text(String(format: "%.2f t", t)).bold() }
                    // Very rough equivalence: ~21.8 kg CO₂ absorbed per tree per year
                    let treesOneYear = co2kg / 21.8
                    HStack { Text("≈ Trees for 1 year"); Spacer(); Text(String(format: "%.0f", treesOneYear)) }
                }
            }
            .navigationTitle("Stats")
        }
    }
}

struct AboutView: View {
    @Binding var compareSheet: Bool
    @EnvironmentObject var store: DataStore
    @State private var showChallenge = false
    @State private var showOffset = false
    @State private var showYearSummary = false
    var body: some View {
        NavigationStack {
            List {
                Section("AvGeek") {
                    Text("Offline aircraft library & route simulator. System Tab Bar (iOS 26) provides Liquid Glass automatically.")
                }
                Section("Quick Actions") {
                    Button { compareSheet = true } label: { Label("Open Compare", systemImage: "square.split.2x1") }
                    Button { showChallenge = true } label: { Label("Route Challenge", systemImage: "flag.checkered") }
                    Button { showOffset = true } label: { Label("CO₂ Offset Calculator", systemImage: "leaf") }
                    Button { showYearSummary = true } label: { Label("Generate Year Summary", systemImage: "calendar") }
                }
                Section("Databases") {
                    Text("Bundle two JSONs: aircraft_db.json (Array<Aircraft>), airports_db.json (Array<Airport>).")
                }
                Section("Flight Rewards") {
                    let earned = computeBadges(store: store).filter { $0.achieved }
                    if earned.isEmpty {
                        Text("No badges yet. Fly more routes to unlock rewards!")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(earned) { b in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(b.title, systemImage: b.icon)
                                Text(b.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showChallenge) { RouteChallengeView().environmentObject(store) }
            .sheet(isPresented: $showOffset) { CO2OffsetView().environmentObject(store) }
            .sheet(isPresented: $showYearSummary) { YearSummaryView().environmentObject(store) }
            .navigationTitle("About")
        }
    }
}

struct RouteChallengeView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var origin: Airport?
    @State private var destination: Airport?
    @State private var picked: Aircraft?
    @State private var result: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge") {
                    Text("We picked a real route. Choose an aircraft to see if it can complete it.")
                }
                Section("Route") {
                    HStack { Text("Origin"); Spacer(); Text(origin?.iata ?? "—").bold() }
                    HStack { Text("Destination"); Spacer(); Text(destination?.iata ?? "—").bold() }
                    Button("New challenge") { pickRandomRoute() }
                }
                Section("Aircraft") {
                    Picker("Type", selection: Binding(get: { picked?.id }, set: { id in picked = id.flatMap { store.aircraft(by: $0) } })) {
                        Text("Select").tag(Optional<String>.none)
                        ForEach(store.aircrafts) { a in Text(a.name).tag(Optional(a.id)) }
                    }
                    Button("Check") { check() }.disabled(origin == nil || destination == nil || picked == nil)
                    if !result.isEmpty { Text(result).bold().foregroundStyle(result.hasPrefix("✅") ? .green : .red) }
                }
            }
            .navigationTitle("Route Challenge")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
            .onAppear { if origin == nil { pickRandomRoute() } }
        }
    }

    private func pickRandomRoute() {
        guard store.airports.count >= 2 else { return }
        var o = store.airports.randomElement()!
        var d = store.airports.randomElement()!
        var tries = 0
        while (o.iata == d.iata || haversineKM(lat1: o.latitude, lon1: o.longitude, lat2: d.latitude, lon2: d.longitude) < 1500) && tries < 30 {
            o = store.airports.randomElement()!
            d = store.airports.randomElement()!
            tries += 1
        }
        origin = o; destination = d; result = ""
    }

    private func check() {
        guard let o = origin, let d = destination, let ac = picked else { return }
        let km = haversineKM(lat1: o.latitude, lon1: o.longitude, lat2: d.latitude, lon2: d.longitude)
        let ok = ac.rangeKM.map { km <= Double($0) } ?? false
        if ok {
            result = "✅ Within range – \(Int(km)) km vs \(ac.rangeKM ?? 0) km"
        } else {
            result = "❌ Out of range – \(Int(km)) km vs \(ac.rangeKM ?? 0) km"
        }
    }
}

struct CO2OffsetView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var years: Double = 1
    var body: some View {
        let co2kg = store.totalEstimatedCO2KG()
        let t = co2kg / 1000.0
        // Rough equivalence: 21.8 kg CO₂ per tree per year
        let treesForYears = (co2kg / 21.8) * years
        NavigationStack {
            Form {
                Section("Total (estimated)") {
                    HStack { Text("CO₂"); Spacer(); Text(String(format: "%.2f t", t)).bold() }
                }
                Section("Offset calculator") {
                    Stepper(value: $years, in: 1...10, step: 1) { Text("Years of offset: \(Int(years))") }
                    HStack { Text("Trees needed"); Spacer(); Text(String(format: "%.0f", treesForYears)).bold() }
                    Text("Assumes ~21.8 kg CO₂ absorbed per tree per year; purely illustrative.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CO₂ Offset")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
        }
    }
}

struct YearSummaryView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var imageURL: URL? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                SummaryCard(store: store)
                    .frame(width: 320, height: 460)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 8)
                    .padding()
                Button("Export as PNG") { exportCard() }
                if let url = imageURL { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                Spacer()
            }
            .navigationTitle("Year Summary")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    private func exportCard() {
#if canImport(UIKit)
        let renderer = ImageRenderer(content: SummaryCard(store: store).frame(width: 1080, height: 1550))
        if let ui = renderer.uiImage, let data = ui.pngData() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("avgeek_summary_\(Int(Date().timeIntervalSince1970)).png")
            try? data.write(to: url, options: [.atomic])
            imageURL = url
        }
#endif
    }
}

struct SummaryCard: View {
    @ObservedObject var store: DataStore
    var body: some View {
        let topAC = store.distanceByAircraft().first?.0
        let totalKm = Int(store.totalDistanceKM)
        let flights = store.totalFlights
        let co2t = store.totalEstimatedCO2KG() / 1000.0
        ZStack {
            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "airplane.circle.fill").imageScale(.large); Text("AviationGeek 2025").font(.title2).bold() }
                Spacer()
                Group {
                    HStack { Text("Total distance"); Spacer(); Text("\(totalKm) km").bold() }
                    HStack { Text("Flights"); Spacer(); Text("\(flights)").bold() }
                    HStack { Text("Top aircraft"); Spacer(); Text(topAC?.name ?? "—").bold() }
                    if let topAirport = store.topAirports(limit: 1).first { HStack { Text("Top airport"); Spacer(); Text(topAirport.0).bold() } }
                    let longest = Int(store.maxSingleFlightKM())
                    if longest > 0 { HStack { Text("Longest flight"); Spacer(); Text("\(longest) km").bold() } }
                    // Badges summary (earned count + top 3 names)
                    let earned = computeBadges(store: store).filter { $0.achieved }
                    HStack { Text("Badges"); Spacer(); Text("\(earned.count)").bold() }
                    let topBadgeStr = earned.prefix(3).map { $0.title }.joined(separator: " • ")
                    if !topBadgeStr.isEmpty {
                        HStack { Text("Top badges"); Spacer(); Text(topBadgeStr).bold().multilineTextAlignment(.trailing) }
                    }
                    HStack { Text("Estimated CO₂"); Spacer(); Text(String(format: "%.2f t", co2t)).bold() }
                }
                .font(.headline)
                Spacer()
                Text("AviationGeek · Offline Av Companion").font(.footnote).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .cornerRadius(24)
    }
}

// ======================================================
// MARK: - Aircraft image resolver
// ======================================================

private func norm(_ s: String) -> String {
    s.lowercased()
     .replacingOccurrences(of: " ", with: "")
     .replacingOccurrences(of: "-", with: "")
     .replacingOccurrences(of: "_", with: "")
}

    private func manufacturerLogoAssetName(for manufacturer: String) -> String? {
        let k = norm(manufacturer)
        let map: [String: String] = [
            "boeing": "boeing",
            "airbus": "airbus",
            "atr": "atr",
            "embraer": "embraer",
            "comac": "comac",
            "irkut": "irkut",
            "sukhoi": "sukhoi",
            "mcdonnelldouglas": "mcdonnelldouglas",
            "dehavilland": "dehavilland",
            "dehavillandcanada": "dehavilland",
            "fokker": "fokker"
        ]
        guard let name = map[k] else { return nil }
#if canImport(UIKit)
        if UIImage(named: name) != nil { return name }
        if UIImage(named: "logos/\(name)") != nil { return "logos/\(name)" }
#endif
        return nil
    }

@ViewBuilder
private func aircraftThumbnail(for ac: Aircraft) -> some View {
#if canImport(UIKit)
    if let first = ac.imageNames.first, UIImage(named: first) != nil {
        Image(first)
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 8))
    } else if let logo = manufacturerLogoAssetName(for: ac.manufacturer) {
        Image(logo)
            .resizable()
            .scaledToFit()
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    } else {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.quaternarySystemFill))
            .overlay(
                Image(systemName: "airplane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
#else
    RoundedRectangle(cornerRadius: 8)
        .fill(Color(.quaternarySystemFill))
        .overlay(
            Image(systemName: "airplane")
                .font(.caption)
                .foregroundStyle(.secondary)
        )
#endif
}

// ======================================================
// MARK: - Flight Rewards (Badges)
// ======================================================

struct RewardBadge: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let achieved: Bool
    let detail: String
}

/// Compute earned and upcoming badges based on total distance and flight count.
@MainActor
func computeBadges(store: DataStore) -> [RewardBadge] {
    let km = Int(store.totalDistanceKM)
    let flights = store.totalFlights

    // Distance milestones (km)
    let distanceMilestones: [(Int, String)] = [
        (10_000, "10k km Club"),
        (50_000, "50k km Club"),
        (100_000, "100k km Club"),
        (250_000, "Quarter-Million Club"),
        (1_000_000, "Million-Kilometer Club")
    ]

    // Flight count milestones
    let flightMilestones: [(Int, String)] = [
        (10, "10 Flights"),
        (50, "50 Flights"),
        (100, "100 Flights")
    ]

    var badges: [RewardBadge] = distanceMilestones.map { (threshold, title) in
        let ok = km >= threshold
        return RewardBadge(
            title: title,
            icon: ok ? "rosette" : "rosette",
            achieved: ok,
            detail: ok ? "Achieved: \(km) km total" : "Next at \(threshold) km • Current: \(km) km"
        )
    }

    badges += flightMilestones.map { (threshold, title) in
        let ok = flights >= threshold
        return RewardBadge(
            title: title,
            icon: ok ? "airplane.circle.fill" : "airplane.circle",
            achieved: ok,
            detail: ok ? "Achieved: \(flights) flights" : "Next at \(threshold) flights • Current: \(flights)"
        )
    }

    let distinctAircraft = Set(store.flights.compactMap { store.aircraft(by: $0.aircraftID)?.id }).count
    let distinctAirports = Set(store.flights.flatMap { [$0.originIATA, $0.destinationIATA] }).count

    let diversity: [(Bool, String, String)] = [
        (distinctAircraft >= 10, "Type Collector", "10+ aircraft types"),
        (distinctAirports >= 20, "Airport Explorer", "20+ unique airports"),
        (distinctAirports >= 50, "World Explorer", "50+ unique airports")
    ]
    for (ok, title, detail) in diversity {
        badges.append(
            RewardBadge(
                title: title,
                icon: ok ? "globe.americas.fill" : "globe.americas",
                achieved: ok,
                detail: ok ? "Achieved: \(detail)" : "Next: \(detail)"
            )
        )
    }
    // Record badges
    let longest = Int(store.maxSingleFlightKM())
    if longest >= 5000 {
        badges.append(RewardBadge(title: "Long-Haul", icon: "airplane", achieved: true, detail: "Longest flight: \(longest) km"))
    } else if longest > 0 {
        badges.append(RewardBadge(title: "Long-Haul", icon: "airplane", achieved: false, detail: "Next: 5000 km • Current: \(longest) km"))
    }

    // Cabin-based badge
    let premium = store.hasPremiumCabinFlight()
    badges.append(RewardBadge(title: "Premium Cabin Flyer", icon: premium ? "crown.fill" : "crown", achieved: premium, detail: premium ? "Flown Business/First" : "Take one Business/First flight"))

    // Hub-lover badge (top airport by visits >= 10)
    if let top = store.visitsByAirport().first, top.1 >= 10 {
        badges.append(RewardBadge(title: "Hub Regular", icon: "building.2.fill", achieved: true, detail: "\(top.0) ×\(top.1) visits"))
    } else if let top = store.visitsByAirport().first {
        badges.append(RewardBadge(title: "Hub Regular", icon: "building.2", achieved: false, detail: "Next: 10 visits to a single airport • Best: \(top.0) ×\(top.1)"))
    }

    return badges
}


// ======================================================
// MARK: - Cabin Badge Helper
// ======================================================

@ViewBuilder
func cabinBadge(_ cabin: CabinClass?) -> some View {
    if let c = cabin {
        // Static colors (no asset dependency)
        let bronze = Color(red: 0.80, green: 0.50, blue: 0.20)
        let silver = Color(red: 0.75, green: 0.75, blue: 0.78)

        // Compute style outside of the result builder to avoid
        // "Type '()' cannot conform to 'View'" and control-flow issues.
        let style: (color: Color, icon: String) = {
            switch c {
            case .economy:         return (.gray,   "circle")          // no badge
            case .premiumEconomy:  return (bronze,  "circle.fill")     // bronze-like
            case .business:        return (silver,  "star.fill")       // silver star
            case .first:           return (.yellow, "crown.fill")      // gold crown
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: style.icon)
            Text(c.rawValue)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(style.color.opacity(0.2)))
        .foregroundStyle(style.color)
    } else {
        EmptyView()
    }
}

// ======================================================
// MARK: - Badge Celebration (Fireworks + Reveal)
// ======================================================

struct BadgeCelebrationView: View {
    let badge: RewardBadge
    let hasMore: Bool
    let showFireworks: Bool
    let onDismiss: () -> Void

    @State private var stage: Stage
    @State private var badgeScale: CGFloat = 0.3
    @State private var badgeRotation: Double = 0
    @State private var sparkleOpacity: Double = 0

    enum Stage { case fireworks, badge }

    init(badge: RewardBadge, hasMore: Bool, showFireworks: Bool, onDismiss: @escaping () -> Void) {
        self.badge = badge
        self.hasMore = hasMore
        self.showFireworks = showFireworks
        self.onDismiss = onDismiss
        _stage = State(initialValue: showFireworks ? .fireworks : .badge)
    }

    var body: some View {
        ZStack {
            if showFireworks {
                FireworksBurstView()
                    .transition(AnyTransition.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.easeOut(duration: 0.4)) { stage = .badge }
                        }
                    }
            }

            if stage == .badge || !showFireworks {
                badgeCard
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !showFireworks {
                stage = .badge
            }
        }
    }

    private var badgeCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.yellow, .orange, .pink, .purple, .blue, .yellow]),
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(badgeRotation))
                    .opacity(sparkleOpacity)

                Image(systemName: badge.icon)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(badgeScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { badgeScale = 1.0 }
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) { badgeRotation = 360 }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { sparkleOpacity = 1.0 }
            }

            VStack(spacing: 12) {
                Text("🎉 Congratulations! 🎉")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .opacity(0.9)

                Text(badge.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if !badge.detail.isEmpty {
                    Text(badge.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: 320)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 12)

            HStack(spacing: 16) {
                Button(action: onDismiss) {
                    if hasMore {
                        Label("Next", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                    } else {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: 300)
        }
        .padding(.horizontal, 20)
    }
}

private struct FireworksBurstView: View {
    var body: some View {
        FireworksView()
    }
}

struct FireworksView: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                drawConfetti(ctx: ctx, size: size, time: t)
            }
        }
        .onAppear { start = Date() }
        .background(confettiBackground)
    }

    private var confettiBackground: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.blue.opacity(0.05),
                Color.purple.opacity(0.08),
                Color.white.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func drawConfetti(ctx: GraphicsContext, size: CGSize, time: Double) {
        let colors: [Color] = [
            Color(red: 0.95, green: 0.55, blue: 0.20),
            Color(red: 0.90, green: 0.32, blue: 0.75),
            Color(red: 0.42, green: 0.67, blue: 0.98),
            Color(red: 0.36, green: 0.83, blue: 0.70),
            Color(red: 0.58, green: 0.50, blue: 0.98)
        ]

        let confettiCount = 220

        for i in 0..<confettiCount {
            let delay = Double(i) * 0.03
            let lifetime = 3.6 + Double(i % 5) * 0.3
            let elapsed = time - delay
            if elapsed < 0 { continue }
            if elapsed > lifetime { continue }

            let progress = elapsed / lifetime
            let eased = ease(progress)

            let column = Double(i % 18)
            let laneWidth = Double(size.width) / 18.0
            let baseX = laneWidth * column + laneWidth * 0.5
            let drift = sin(elapsed * 1.4 + column) * laneWidth * 0.35
            let x = baseX + drift

            let startY = -Double(size.height) * 0.1
            let endY = Double(size.height) * 1.1
            let y = startY + (endY - startY) * eased

            let spin = elapsed * 3.0 + Double(i % 6) * .pi / 6

            let color = colors[i % colors.count].opacity(0.92)

            var pieceCtx = ctx
            pieceCtx.translateBy(x: x, y: y)
            pieceCtx.rotate(by: Angle(radians: spin))

            let baseSize: CGFloat = 9 + CGFloat(i % 4) * 1.3
            let pathType = i % 5

            switch pathType {
            case 0:
                let rect = CGRect(x: -baseSize/2, y: -baseSize*1.8/2, width: baseSize, height: baseSize*1.8)
                pieceCtx.fill(Path(roundedRect: rect, cornerRadius: baseSize * 0.35), with: .color(color))
            case 1:
                let rect = CGRect(x: -baseSize/2, y: -baseSize/2, width: baseSize, height: baseSize)
                pieceCtx.fill(Path(ellipseIn: rect), with: .color(color))
            case 2:
                var path = Path()
                path.move(to: CGPoint(x: -baseSize * 0.6, y: baseSize * 0.6))
                path.addLine(to: CGPoint(x: 0, y: -baseSize * 0.8))
                path.addLine(to: CGPoint(x: baseSize * 0.6, y: baseSize * 0.6))
                path.closeSubpath()
                pieceCtx.fill(path, with: .color(color))
            case 3:
                let rect = CGRect(x: -baseSize * 0.5, y: -baseSize * 2.1 / 2, width: baseSize, height: baseSize * 2.1)
                pieceCtx.fill(Path(roundedRect: rect, cornerRadius: baseSize * 0.15), with: .color(color))
                let accentRect = rect.insetBy(dx: baseSize * 0.2, dy: baseSize * 0.2)
                pieceCtx.stroke(Path(roundedRect: accentRect, cornerRadius: baseSize * 0.12), with: .color(Color.white.opacity(0.35)), lineWidth: 1)
            default:
                let rect = CGRect(x: -baseSize/2, y: -baseSize * 1.4 / 2, width: baseSize, height: baseSize * 1.4)
                pieceCtx.fill(Path(roundedRect: rect, cornerRadius: baseSize * 0.45), with: .color(color))
            }
        }
    }

    private func ease(_ t: Double) -> Double {
        // smooth ease-out to slow near the bottom
        let clamped = max(0, min(1, t))
        return 1 - pow(1 - clamped, 3)
    }

    private enum ConfettiShape { case rectangle, capsule, triangle }
}

// ======================================================
// MARK: - Utils
// ======================================================

func haversineKM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let R = 6371.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat/2)*sin(dLat/2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon/2)*sin(dLon/2)
    return R * 2 * atan2(sqrt(a), sqrt(1-a))
}

#if canImport(UIKit)
extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
}
#endif


