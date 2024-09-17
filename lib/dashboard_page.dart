import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'profile_page.dart'; 
import 'result_page.dart'; 


class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _activityController = TextEditingController();
  Position? _currentPosition;
  bool _isRecording = false;
  List<Position> _recordedPositions = [];
  double _distance = 0.0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever ||
            permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location permission is denied.')),
          );
          return;
        }
      }

      _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get current location: $e')),
      );
    }
  }

  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);
      Placemark place = placemarks.first;
      return '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}';
    } catch (e) {
      return 'Unknown location';
    }
  }

  Future<void> _addParkingLocation(String activityName) async {
    String time = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    String locationName = 'Unknown';

    if (_currentPosition != null) {
      locationName = await _getLocationName(
          _currentPosition!.latitude, _currentPosition!.longitude);
    }

    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No user logged in')),
        );
        return;
      }

      String uid = user.uid;

      QuerySnapshot activeSnapshot = await _firestore
          .collection('parkingLocations')
          .where('status', isEqualTo: 'Active')
          .where('uid', isEqualTo: uid)
          .get();

      if (activeSnapshot.docs.isNotEmpty) {
        for (var doc in activeSnapshot.docs) {
          await _firestore.collection('parkingLocations').doc(doc.id).update({
            'status': 'Completed',
            'endTime': time,
          });
        }
      }

      await _firestore.collection('parkingLocations').add({
        'uid': uid,
        'location': locationName,
        'activity': activityName,
        'time': time,
        'endTime': null,
        'status': 'Active',
        'recordedPositions': [], // Initialize with empty list
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add parking location: $e')),
      );
    }
  }

  Future<void> _updateParkingStatus(String id, String newStatus) async {
    try {
      String time = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      if (newStatus == 'Completed') {
        await _firestore.collection('parkingLocations').doc(id).update({
          'status': newStatus,
          'endTime': time,
        });
      } else if (newStatus == 'Active') {
        final User? user = _auth.currentUser;
        if (user != null) {
          QuerySnapshot activeSnapshot = await _firestore
              .collection('parkingLocations')
              .where('status', isEqualTo: 'Active')
              .where('uid', isEqualTo: user.uid)
              .get();

          if (activeSnapshot.docs.isNotEmpty) {
            for (var doc in activeSnapshot.docs) {
              await _firestore
                  .collection('parkingLocations')
                  .doc(doc.id)
                  .update({
                'status': 'Completed',
                'endTime': time,
              });
            }
          }
        }

        await _firestore.collection('parkingLocations').doc(id).update({
          'status': newStatus,
          'endTime': null,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update parking status: $e')),
      );
    }
  }

  Future<void> _deleteParkingLocation(String id) async {
    try {
      await _firestore.collection('parkingLocations').doc(id).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete location: $e')),
      );
    }
  }

  Future<void> _startRecording(String id) async {
    setState(() {
      _isRecording = true;
      _recordedPositions = [];
    });

    // Start periodic location updates
    Geolocator.getPositionStream().listen((position) {
      setState(() {
        _currentPosition = position;
        _recordedPositions.add(position);
      });
    });
  }

  Future<void> _stopRecording(String id) async {
  setState(() {
    _isRecording = false;
  });

  // Save recorded positions to Firestore
  final recordedData = {
    'recordedPositions': _recordedPositions
        .map((pos) => {'latitude': pos.latitude, 'longitude': pos.longitude})
        .toList(),
  };
  await _firestore
      .collection('parkingLocations')
      .doc(id)
      .update(recordedData);

  // Calculate distance between start and end points
  if (_recordedPositions.length >= 2) {
    double distance = Geolocator.distanceBetween(
      _recordedPositions.first.latitude,
      _recordedPositions.first.longitude,
      _recordedPositions.last.latitude,
      _recordedPositions.last.longitude,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Recording stopped. Distance: ${distance.toStringAsFixed(2)} meters')),
    );

    // Navigate to ResultPage with the distance
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultPage(distance: distance),
      ),
    );
  }
}



  void _showAddParkingDialog() {
    String activityName = '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Parking Location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _activityController,
                onChanged: (value) {
                  activityName = value;
                },
                decoration:
                    const InputDecoration(hintText: 'Enter activity name'),
              ),
              if (_currentPosition != null)
                Text(
                    'Current Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (activityName.isNotEmpty) {
                  _addParkingLocation(activityName);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateStatusDialog(String id, String currentStatus) {
    String newStatus = currentStatus;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Parking Status'),
          content: DropdownButton<String>(
            value: newStatus,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Active')),
              DropdownMenuItem(value: 'Completed', child: Text('Completed')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  newStatus = value;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _updateParkingStatus(id, newStatus);
                if (newStatus == 'Completed') {
                  await _stopRecording(
                      id); // Stop recording if status is Completed
                }
                Navigator.of(context).pop();
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(String id) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Parking Location'),
          content: const Text('Are you sure you want to delete this location?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _deleteParkingLocation(id);
                Navigator.of(context).pop();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.currentUser;
    if (user == null) {
      // Redirect to login page if user is not authenticated
      Navigator.pushReplacementNamed(context, '/');
      return const Center(child: CircularProgressIndicator());
    }

    String uid = user.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),
        ],
        backgroundColor: Colors.black.withOpacity(0.8),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF000000),
              Color(0xFF3C3C3C),
            ],
            stops: [0.1, 0.9],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('parkingLocations')
              .where('uid', isEqualTo: uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                  child: Text('No parking locations added yet'));
            }

            final parkingLocations = snapshot.data!.docs;
            return ListView.builder(
              itemCount: parkingLocations.length,
              itemBuilder: (context, index) {
                final parking =
                    parkingLocations[index].data() as Map<String, dynamic>;
                final String id = parkingLocations[index].id;
                final String status = parking['status'];
                final String location = parking['location'];
                final String time = parking['time'];
                final String activity = parking['activity'];

                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                  color: Colors.black.withOpacity(0.6),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    title: Text(
                      '$location - $activity',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Status: $status\nStart time: $time',
                      style: TextStyle(
                        color: Colors.grey[400],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (status == 'Active')
                          IconButton(
                            icon: Icon(
                              _isRecording
                                  ? Icons.stop
                                  : Icons.fiber_manual_record,
                              color:
                                  _isRecording ? Colors.red : Colors.blueAccent,
                            ),
                            onPressed: () {
                              if (_isRecording) {
                                _stopRecording(id);
                              } else {
                                _startRecording(id);
                              }
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            Icons.edit,
                            color: Colors.blueAccent,
                          ),
                          onPressed: () {
                            _showUpdateStatusDialog(id, status);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            _showDeleteConfirmationDialog(id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddParkingDialog,
        child: const Icon(Icons.add),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }
}
