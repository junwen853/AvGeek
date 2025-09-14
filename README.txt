# AviationGeek ✈️

**AviationGeek** is a modern iOS application built for aviation enthusiasts, hobbyists, and frequent flyers.  
The app serves as a personal companion where you can browse aircraft data, simulate routes, record flights, and view your flying statistics — all completely offline.

## ✨ Key Features
- **Aircraft Library**  
  Explore a detailed collection of aircraft with information such as manufacturer, category, production status, first flight, range, and seating. Search easily by name, IATA/ICAO code, or manufacturer.  
- **Route Simulator**  
  Choose an origin and destination airport to calculate great-circle distance and estimated flight time. The simulator checks whether your selected aircraft can complete the route within its range.  
- **Flight Logbook**  
  Save your personal flights with date, origin, destination, aircraft type, and optional notes. All entries are stored on-device and can be exported or imported as JSON.  
- **Statistics & Rewards**  
  Instantly view total flights, total kilometers flown, and breakdowns by aircraft or manufacturer. Unlock milestone badges (10k km, 50 flights, etc.) to celebrate your progress.  
- **Onboarding Guide**  
  First-time users are greeted with a colorful, animated multi-page guide that highlights the core features of the app.  
- **Modern Design**  
  Built with SwiftUI, supporting iOS 16+ and optimized for iOS 26 with the new Liquid Glass tab bar effect.

## 🛠️ Technical Details
- SwiftUI + UIKit integration  
- Local JSON databases for aircraft and airports  
- Flight data persistence with `UserDefaults` and JSON export/import  
- Adaptive dark/light mode support  

## 🚀 Getting Started
1. Clone the repository  
   ```bash
   git clone https://github.com/your-username/AviationGeek.git