/// Compatibility shim.
///
/// The theme now lives in `lib/design/`. This re-export keeps existing
/// imports working during the migration; once every call site imports
/// `design/app_theme.dart` directly this file is deleted.
library;

export 'design/app_theme.dart';

import 'package:flutter/material.dart';

import 'design/app_theme.dart';

@Deprecated('Use buildAppTheme() from design/app_theme.dart')
ThemeData buildTheme() => buildAppTheme();
