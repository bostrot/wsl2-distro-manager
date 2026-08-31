import 'dart:io';

import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/vm/vm_backend.dart';
import 'package:wsl2distromanager/api/wsl.dart';

/// Whether this host manages instances through Apple's
/// Virtualization.framework rather than WSL.
bool get isAppleHost => Platform.isMacOS;

/// Builds the [VmBackend] for this host. Replaced by tests to inject fakes;
/// production code always calls [vmBackend] instead of constructing a
/// backend directly, so the whole app follows one switch.
VmBackend Function() vmBackendBuilder = defaultVmBackendBuilder;

VmBackend defaultVmBackendBuilder() =>
    isAppleHost ? AppleVmApi() : WSLApi();

/// The instance backend for this host.
VmBackend vmBackend() => vmBackendBuilder();
