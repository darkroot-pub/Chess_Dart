import 'package:flutter/material.dart';

/// Lets services (e.g. incoming challenges) open screens without a BuildContext.
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
