// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_planetscale/otel_planetscale.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_planetscale-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SELECT records CLIENT span with parsed operation', () async {
    await tracedPlanetscaleQuery<String>(
      statement: 'SELECT * FROM orders WHERE id = ?',
      database: 'shop',
      branch: 'main',
      collection: 'orders',
      invoke: () async => const PlanetscaleQueryResult(value: 'rows'),
    );
    final span = spans.findSpanByName('SELECT orders');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'mysql');
    expect(a['db.name'], 'shop');
    expect(a['db.statement'], 'SELECT * FROM orders WHERE id = ?');
    expect(a['db.operation'], 'SELECT');
    expect(a['db.collection.name'], 'orders');
    expect(a['planetscale.database'], 'shop');
    expect(a['planetscale.branch'], 'main');
    expect(a['planetscale.driver'], 'serverless');
  });

  test('INSERT records rows_affected + insert_id', () async {
    await tracedPlanetscaleQuery<String>(
      statement: 'INSERT INTO orders (id) VALUES (?)',
      database: 'shop',
      invoke: () async => const PlanetscaleQueryResult(
        value: 'ok',
        rowsAffected: 1,
        insertId: '999',
      ),
    );
    final a = attrsOf(spans.findSpanByName('INSERT')!);
    expect(a['db.rows_affected'], 1);
    expect(a['planetscale.insert_id'], '999');
  });

  test('truncates very long statement', () async {
    final long = 'SELECT ${'a,' * 700}b FROM t';
    await tracedPlanetscaleQuery<String>(
      statement: long,
      database: 'shop',
      invoke: () async => const PlanetscaleQueryResult(value: 'ok'),
    );
    final a = attrsOf(spans.findSpanByName('SELECT')!);
    expect((a['db.statement']! as String).length, 1024);
  });

  test('records exception', () async {
    await expectLater(
      tracedPlanetscaleQuery<String>(
        statement: 'SELECT 1',
        database: 'shop',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      spans.findSpanByName('SELECT')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutPlanetscaleInstrumentationAsync(() async {
      await tracedPlanetscaleQuery<String>(
        statement: 'SELECT 1',
        database: 'shop',
        invoke: () async => const PlanetscaleQueryResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('SELECT'), isEmpty);
  });
}
