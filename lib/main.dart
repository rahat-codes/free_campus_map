
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const CampusNavigatorApp());
}

class CampusNavigatorApp extends StatelessWidget {
  const CampusNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tongmyong Campus Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const CampusNavigationScreen(),
    );
  }
}

class CampusPlace {
  final String id;
  final String name;
  final String category;
  final LatLng position;

  const CampusPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.position,
  });
}

class CampusNavigationScreen extends StatefulWidget {
  const CampusNavigationScreen({super.key});

  @override
  State<CampusNavigationScreen> createState() =>
      _CampusNavigationScreenState();
}

class _CampusNavigationScreenState
    extends State<CampusNavigationScreen> {
  final MapController _mapController = MapController();

  // Approximate center used only to open the campus map and
  // search nearby OpenStreetMap features. Not a building coordinate.
  static const LatLng _campusViewCenter =
  LatLng(35.1236, 129.1017);

  static const String _overpassEndpoint =
      'https://overpass-api.de/api/interpreter';

  static const String _walkingRouter =
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving';

  static const String _appUserAgent =
      'TongmyongCampusNavigator/1.0';

  final List<CampusPlace> _places = [];
  final List<LatLng> _routePoints = [];

  LatLng? _currentLocation;
  CampusPlace? _destination;

  StreamSubscription<Position>? _positionSubscription;

  bool _satelliteMode = true;
  bool _loadingPlaces = false;
  bool _loadingRoute = false;
  bool _trackingLocation = false;

  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteRequestAt;

  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadCampusPlaces();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // Discover actual named map features. Coordinates come from
  // OpenStreetMap responses, not from hard-coded building guesses.
  Future<void> _loadCampusPlaces() async {
    if (_loadingPlaces) return;

    setState(() {
      _loadingPlaces = true;
      _statusMessage = 'Finding mapped campus places...';
    });

    const String query = '''
[out:json][timeout:25];
(
  node(around:1500,35.1236,129.1017)["name"]["amenity"];
  node(around:1500,35.1236,129.1017)["name"]["shop"];
  node(around:1500,35.1236,129.1017)["name"]["tourism"];
  node(around:1500,35.1236,129.1017)["name"]["leisure"];
  node(around:1500,35.1236,129.1017)["name"]["office"];
  way(around:1500,35.1236,129.1017)["name"]["building"];
  way(around:1500,35.1236,129.1017)["name"]["amenity"];
  way(around:1500,35.1236,129.1017)["name"]["shop"];
  way(around:1500,35.1236,129.1017)["name"]["leisure"];
  way(around:1500,35.1236,129.1017)["name"]["office"];
  way(around:1500,35.1236,129.1017)["name"]["tourism"];
  way(around:1500,35.1236,129.1017)["name"]["education"];
  relation(around:1500,35.1236,129.1017)["name"]["amenity"];
  relation(around:1500,35.1236,129.1017)["name"]["building"];
);
out center tags;
''';

    try {
      final response = await http
          .post(
        Uri.parse(_overpassEndpoint),
        headers: {
          'User-Agent': _appUserAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'data': query},
      )
          .timeout(const Duration(seconds: 35));

      if (response.statusCode != 200) {
        throw Exception(
          'Map data service returned HTTP ${response.statusCode}.',
        );
      }

      final decoded =
      jsonDecode(response.body) as Map<String, dynamic>;

      final elements = decoded['elements'] as List<dynamic>? ?? [];
      final List<CampusPlace> found = [];
      final Set<String> seen = {};

      for (final raw in elements) {
        final element = raw as Map<String, dynamic>;
        final tags =
            element['tags'] as Map<String, dynamic>? ?? {};

        final name = tags['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        double? lat;
        double? lon;

        // OSM nodes have coordinates directly. Ways and relations
        // may provide a representative center coordinate.
        if (element['lat'] is num && element['lon'] is num) {
          lat = (element['lat'] as num).toDouble();
          lon = (element['lon'] as num).toDouble();
        } else {
          final center =
          element['center'] as Map<String, dynamic>?;

          if (center?['lat'] is num && center?['lon'] is num) {
            lat = (center!['lat'] as num).toDouble();
            lon = (center['lon'] as num).toDouble();
          }
        }

        if (lat == null || lon == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
          continue;
        }

        final id = '${element['type']}/${element['id']}';
        if (!seen.add(id)) continue;

        final category = tags['amenity']?.toString() ??
            tags['building']?.toString() ??
            tags['shop']?.toString() ??
            tags['tourism']?.toString() ??
            tags['leisure']?.toString() ??
            tags['office']?.toString() ??
            tags['education']?.toString() ??
            'Mapped place';

        found.add(
          CampusPlace(
            id: id,
            name: name,
            category: category.replaceAll('_', ' '),
            position: LatLng(lat, lon),
          ),
        );
      }

      found.sort(
            (a, b) => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      );

      if (!mounted) return;

      setState(() {
        _places
          ..clear()
          ..addAll(found);
        _statusMessage = found.isEmpty
            ? 'No named places found. Try refreshing later.'
            : '${found.length} mapped places found';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Could not load campus places.';
      });

      _showMessage(
        'Could not load places. Check your internet connection '
            'or try again later. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlaces = false;
        });
      }
    }
  }

  Future<void> _startLiveLocation() async {
    try {
      final enabled =
      await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        _showMessage(
          'Turn on Location Services on your device first.',
        );
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage('Location permission was denied.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Enable location permission in your app settings.',
        );
        await Geolocator.openAppSettings();
        return;
      }

      final initialPosition =
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      if (!mounted) return;

      final initialPoint = LatLng(
        initialPosition.latitude,
        initialPosition.longitude,
      );

      setState(() {
        _currentLocation = initialPoint;
        _trackingLocation = true;
      });

      _mapController.move(initialPoint, 18);

      await _positionSubscription?.cancel();

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
            (position) {
          if (!mounted) return;

          final point = LatLng(
            position.latitude,
            position.longitude,
          );

          setState(() {
            _currentLocation = point;
          });

          // Recalculate occasionally as the user moves, not on
          // every GPS update, to respect the public router limits.
          final previousOrigin = _lastRouteOrigin;
          final lastRequest = _lastRouteRequestAt;

          if (_destination != null &&
              !_loadingRoute &&
              previousOrigin != null &&
              Geolocator.distanceBetween(
                previousOrigin.latitude,
                previousOrigin.longitude,
                point.latitude,
                point.longitude,
              ) >=
                  40 &&
              (lastRequest == null ||
                  DateTime.now().difference(lastRequest).inSeconds >=
                      15)) {
            unawaited(_calculateWalkingRoute(silent: true));
          }
        },
        onError: (Object error) {
          if (mounted) {
            _showMessage('GPS update failed: $error');
          }
        },
      );

      if (_destination != null) {
        await _calculateWalkingRoute();
      } else {
        _showMessage(
          'GPS is active. Choose a destination to get a route.',
        );
      }
    } catch (error) {
      _showMessage('Could not get your location: $error');
    }
  }

  Future<void> _chooseDestination() async {
    if (_places.isEmpty && !_loadingPlaces) {
      await _loadCampusPlaces();
    }

    if (!mounted) return;

    final place = await showModalBottomSheet<CampusPlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Choose a mapped destination',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'These places are retrieved from OpenStreetMap. '
                        'Some campus buildings may be missing.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _places.isEmpty
                      ? const Center(
                    child: Text(
                      'No mapped places available. '
                          'Try again later.',
                    ),
                  )
                      : ListView.builder(
                    itemCount: _places.length,
                    itemBuilder: (context, index) {
                      final place = _places[index];

                      return ListTile(
                        leading: const Icon(
                          Icons.location_on_outlined,
                        ),
                        title: Text(place.name),
                        subtitle: Text(place.category),
                        onTap: () {
                          Navigator.pop(context, place);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (place == null || !mounted) return;

    setState(() {
      _destination = place;
      _routePoints.clear();
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _lastRouteOrigin = null;
    });

    _mapController.move(place.position, 18);

    if (_currentLocation == null) {
      _showMessage('First tap the location button to enable GPS.');
      return;
    }

    await _calculateWalkingRoute();
  }

  Future<void> _calculateWalkingRoute({
    bool silent = false,
  }) async {
    final start = _currentLocation;
    final destination = _destination;

    if (start == null || destination == null) {
      if (!silent) {
        _showMessage(
          'Enable GPS and select a destination first.',
        );
      }
      return;
    }

    if (_loadingRoute) return;

    setState(() {
      _loadingRoute = true;
      if (!silent) {
        _statusMessage = 'Calculating walking route...';
      }
    });

    _lastRouteRequestAt = DateTime.now();

    try {
      final url = Uri.parse(
        '$_walkingRouter/'
            '${start.longitude},${start.latitude};'
            '${destination.position.longitude},'
            '${destination.position.latitude}'
            '?overview=full&geometries=geojson&steps=true',
      );

      final response = await http
          .get(
        url,
        headers: {'User-Agent': _appUserAgent},
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception(
          'Walking router returned HTTP ${response.statusCode}.',
        );
      }

      final decoded =
      jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['code'] != 'Ok') {
        throw Exception(
          decoded['message']?.toString() ??
              'No walking route was found.',
        );
      }

      final routes = decoded['routes'] as List<dynamic>? ?? [];

      if (routes.isEmpty) {
        throw Exception('No walking route was found.');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry =
      route['geometry'] as Map<String, dynamic>;
      final coordinates =
      geometry['coordinates'] as List<dynamic>;

      final points = coordinates.map<LatLng>((coordinate) {
        final pair = coordinate as List<dynamic>;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();

      if (points.isEmpty) {
        throw Exception('The returned route has no geometry.');
      }

      if (!mounted) return;

      setState(() {
        _routePoints
          ..clear()
          ..addAll(points);

        _routeDistanceMeters =
            (route['distance'] as num?)?.toDouble();

        _routeDurationSeconds =
            (route['duration'] as num?)?.toDouble();

        _lastRouteOrigin = start;
        _statusMessage = 'Walking route ready';
      });

      if (!silent) {
        _showMessage('Walking route calculated.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _routePoints.clear();
          _routeDistanceMeters = null;
          _routeDurationSeconds = null;
          _statusMessage = 'Route unavailable';
        });

        if (!silent) {
          _showMessage(
            'Could not calculate a walking route. '
                'Check connectivity, mapped paths, or try later. $error',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
    }
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '--';

    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }

    return '${meters.round()} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '--';

    final minutes = (seconds / 60).round();

    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    return '${hours}h ${remaining}m';
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    for (final place in _places) {
      final selected = place.id == _destination?.id;

      markers.add(
        Marker(
          point: place.position,
          width: 44,
          height: 52,
          child: GestureDetector(
            onTap: () async {
              setState(() {
                _destination = place;
                _routePoints.clear();
                _routeDistanceMeters = null;
                _routeDurationSeconds = null;
                _lastRouteOrigin = null;
              });

              _mapController.move(place.position, 18);

              if (_currentLocation != null) {
                await _calculateWalkingRoute();
              } else {
                _showMessage(
                  'Enable GPS to route to ${place.name}.',
                );
              }
            },
            child: Icon(
              selected ? Icons.location_on : Icons.place,
              size: selected ? 42 : 32,
              color: selected ? Colors.deepOrange : Colors.blue,
            ),
          ),
        ),
      );
    }

    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 36,
          ),
        ),
      );
    }

    if (_destination != null) {
      markers.add(
        Marker(
          point: _destination!.position,
          width: 44,
          height: 52,
          child: const Icon(
            Icons.flag,
            size: 42,
            color: Colors.red,
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final imageryAttribution = _satelliteMode
        ? 'Imagery © Esri, Vantor, Earthstar Geographics, '
        'and the GIS User Community'
        : '© OpenStreetMap contributors';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Navigator'),
        actions: [
          IconButton(
            tooltip: _satelliteMode
                ? 'Switch to street map'
                : 'Switch to satellite',
            onPressed: () {
              setState(() {
                _satelliteMode = !_satelliteMode;
              });
            },
            icon: Icon(
              _satelliteMode
                  ? Icons.map_outlined
                  : Icons.satellite_alt,
            ),
          ),
          IconButton(
            tooltip: 'Refresh mapped places',
            onPressed: _loadingPlaces ? null : _loadCampusPlaces,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _campusViewCenter,
              initialZoom: 17,
              minZoom: 3,
              maxZoom: 20,
            ),
            children: [
              TileLayer(
                urlTemplate: _satelliteMode
                    ? 'https://services.arcgisonline.com/'
                    'ArcGIS/rest/services/World_Imagery/'
                    'MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',
                userAgentPackageName:
                'com.example.free_campus_map',
              ),
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 6,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
              SimpleAttributionWidget(
                alignment: Alignment.bottomLeft,
                source: Text(imageryAttribution),
              ),
            ],
          ),

          // Search and destination controls.
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.search,
                        color: Colors.blue,
                      ),
                      title: Text(
                        _destination?.name ??
                            'Where do you want to go?',
                      ),
                      subtitle: Text(
                        _destination == null
                            ? (_statusMessage ??
                            'Choose a mapped campus place')
                            : _destination!.category,
                      ),
                      trailing: _loadingPlaces || _loadingRoute
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.keyboard_arrow_down),
                      onTap: _chooseDestination,
                    ),
                    if (_destination != null &&
                        _routeDistanceMeters != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                          children: [
                            _InfoItem(
                              icon: Icons.route,
                              label: 'Distance',
                              value: _formatDistance(
                                _routeDistanceMeters,
                              ),
                            ),
                            _InfoItem(
                              icon: Icons.schedule,
                              label: 'Walking time',
                              value: _formatDuration(
                                _routeDurationSeconds,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Location, campus and route controls.
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'location_button',
                  tooltip: 'Start live GPS',
                  onPressed: _startLiveLocation,
                  child: Icon(
                    _trackingLocation
                        ? Icons.gps_fixed
                        : Icons.my_location,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'campus_button',
                  tooltip: 'Return to campus view',
                  onPressed: () {
                    _mapController.move(_campusViewCenter, 17);
                  },
                  child: const Icon(Icons.school),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'route_button',
                  onPressed: _loadingRoute
                      ? null
                      : () => _destination == null
                      ? _chooseDestination()
                      : _calculateWalkingRoute(),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Get route'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
