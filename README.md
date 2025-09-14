# AvGeek

**AvGeek** is an iOS app for aviation enthusiasts, built with SwiftUI.  
It works fully **offline**, providing an aircraft library, route simulator, logbook, stats, and rewards.  
Users can browse aircraft, simulate flights, track mileage, and unlock badges.  
The app also introduces new geek features like route challenges, CO₂ offset calculator, and yearly flight summary cards.

## ✈️ Features
- **Aircraft Library**: Browse by manufacturer, status, and category with logos and images.
- **Route Simulator**: Pick origin & destination airports, compute great-circle distance, estimated time, fuel burn, and CO₂ emissions.
- **Flight Logbook**: Save flights with date, notes, and cabin class.
- **Stats & Badges**: Totals by aircraft/manufacturer, distance milestones, flight counts, and diversity badges.
- **Compare View**: Select two aircraft and compare specs side by side.
- **Onboarding**: Colorful multi-page welcome guide with animations.
- **Liquid Glass Tab Bar**: Native iOS 26 styling.

## 🆕 New Features
- **Route Challenge**: Random real-world routes where you test if your aircraft can make the distance.  
- **Top 3 Aircraft Leaderboard**: Shows your most flown aircraft types by distance.  
- **CO₂ Offset Calculator**: Converts your emissions into “trees needed per year.”  
- **Yearly Summary Card**: Generates a shareable PNG card with your total distance, flights, top aircraft, and CO₂.  

## 🚀 Tech
- SwiftUI (iOS 17+ / iOS 26 for native Liquid Glass tab bar)
- JSON-based offline database (`aircraft_db.json`, `airports_db.json`)
- Data persistence for flight logs & favorites
- ImageRenderer for summary card export
