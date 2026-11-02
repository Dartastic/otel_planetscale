// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_planetscale/otel_planetscale.dart';

/// Traces Planetscale calls with OpenTelemetry.
///
/// `otel_planetscale` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Planetscale call in
/// [tracedPlanetscaleQuery]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'planetscale-example');

  // Wraps a PlanetScale serverless-driver query in a CLIENT span, recording the SQL statement (truncated), database, branch, and rows affected.
  final planetscaleQueryId = await tracedPlanetscaleQuery<String>(
    statement: 'active',
    database: 'example',
    branch: 'example',
    collection: 'orders',
    invoke: () async {
      // Make the Planetscale call here, then report what it returned.
      const id = 'planetscale_8f3a2c';
      return const PlanetscaleQueryResult(
          value: id, rowsAffected: 1, insertId: 'insert_8f3a2c');
    },
  );
  OTelLog.info('tracedPlanetscaleQuery returned $planetscaleQueryId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutPlanetscaleInstrumentationAsync.
  await runWithoutPlanetscaleInstrumentationAsync(
    () => tracedPlanetscaleQuery<String>(
      statement: 'active',
      database: 'example',
      branch: 'example',
      collection: 'orders',
      invoke: () async {
        const id = 'planetscale_8f3a2c';
        return const PlanetscaleQueryResult(
            value: id, rowsAffected: 1, insertId: 'insert_8f3a2c');
      },
    ),
  );

  await OTel.shutdown();
}
