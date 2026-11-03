# Free Campus Map

<div align="center">

<p><strong>CAMPUS NAVIGATION PROTOTYPE</strong></p>

<img src="https://img.shields.io/badge/Flutter-0F172A?style=for-the-badge" alt="Flutter" />
<img src="https://img.shields.io/badge/Dart-0F172A?style=for-the-badge" alt="Dart" />
<img src="https://img.shields.io/badge/OpenStreetMap-0F172A?style=for-the-badge" alt="OpenStreetMap" />

<a href="https://github.com/rahat-codes/free_campus_map"><img src="https://img.shields.io/github/stars/rahat-codes/free_campus_map?style=social" alt="GitHub stars" /></a>

</div>

---

A Flutter campus-navigation prototype centered on the Tongmyong University area in Busan, South Korea. The app combines an interactive map, OpenStreetMap place discovery, device location, and walking-route requests.

> **Project status:** Prototype. Place coverage and route availability depend on third-party OpenStreetMap services and their data. The initial map center is an approximate viewing location, not a verified building coordinate.

## Features

- Interactive map built with `flutter_map`.
- OpenStreetMap map tiles and an optional satellite imagery layer.
- Nearby named-place discovery using the Overpass API.
- Current-device location using `geolocator`.
- Destination selection and walking-route requests.
- Route distance and estimated duration display.
- Asynchronous loading and user-facing error messages for external service failures.

## Technology Stack

| Area | Technology |
|---|---|
| Mobile application | Flutter, Dart |
| Map rendering | flutter_map |
| Coordinates and distance | latlong2 |
| Device location | geolocator |
| HTTP requests | http |
| Place discovery | OpenStreetMap Overpass API |
| Map data | OpenStreetMap; satellite imagery layer |

## Application Structure

The current prototype keeps its implementation primarily in one file:

```text
lib/
└── main.dart
```

The main file currently contains the app entry point, place model, map screen, API requests, location handling, route state, and map UI.

**Engineering improvement opportunity:** split this prototype into feature-oriented modules (for example, `models/`, `services/`, `screens/`, and `widgets/`) and add unit/widget tests as the project grows.

## Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`
- Android Studio or Visual Studio Code
- An Android/iOS device or emulator
- Internet access for map tiles, Overpass place data, and route requests
- Location permission and device location services for live positioning

## Run Locally

```bash
git clone https://github.com/rahat-codes/free_campus_map.git
cd free_campus_map
flutter pub get
flutter analyze
flutter run
```

## External Services and Data

- [OpenStreetMap](https://www.openstreetmap.org/) provides map data.
- [Overpass API](https://overpass-api.de/) is used to discover named places.
- [OpenStreetMap routing service](https://routing.openstreetmap.de/) is used for route requests.
- The app also uses a third-party satellite imagery tile source.

These services are independent of this app. Their availability, rate limits, attribution requirements, and data coverage may change. Do not treat map results as authoritative campus facility records.

## Privacy and Permissions

Live location requires the operating system's location permission. The app requests location access when the user starts location tracking. Review the platform permission declarations before distributing a production build.

## Roadmap

- [ ] Separate map, location, place-search, and routing services from the screen widget.
- [ ] Add unit tests for coordinate and route-response parsing.
- [ ] Add widget tests for loading, empty, and error states.
- [ ] Add retry/backoff and clearer API rate-limit handling.
- [ ] Add a verified campus dataset and distinguish official facilities from community-mapped places.
- [ ] Add screenshots and a short screen recording.
- [ ] Document attribution and production tile-service requirements.

## Author

**Rahat** · [GitHub](https://github.com/rahat-codes)
