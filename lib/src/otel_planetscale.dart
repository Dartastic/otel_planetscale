// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_planetscale_suppression.dart';

const _tracerName = 'dartastic_otel_libs_planetscale';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedPlanetscaleQuery` callback.
class PlanetscaleQueryResult<T> {
  const PlanetscaleQueryResult({
    required this.value,
    this.rowsAffected,
    this.insertId,
  });
  final T value;
  final int? rowsAffected;
  final String? insertId;
}

const _maxStatementLength = 1024;

String _truncate(String s) =>
    s.length <= _maxStatementLength ? s : s.substring(0, _maxStatementLength);

/// Wraps a PlanetScale serverless-driver query in a CLIENT span,
/// recording the SQL statement (truncated), database, branch, and
/// rows affected. db.system is `mysql` (PlanetScale speaks MySQL
/// wire protocol).
Future<T> tracedPlanetscaleQuery<T>({
  required String statement,
  required String database,
  required Future<PlanetscaleQueryResult<T>> Function() invoke,
  String? branch,
  String? operation,
  String? collection,
}) async {
  if (planetscaleInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final op = operation ?? _operationFromStatement(statement);
  final m = <String, Object>{
    'db.system': 'mysql',
    'db.name': database,
    'db.statement': _truncate(statement),
    'planetscale.database': database,
    'planetscale.driver': 'serverless',
    if (op != null) 'db.operation': op,
    if (collection != null) 'db.collection.name': collection,
  };
  if (branch != null) m['planetscale.branch'] = branch;

  final spanName =
      collection == null ? (op ?? 'query') : '${op ?? 'query'} $collection';
  final span = _tracer().startSpan(
    spanName,
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.rowsAffected != null) {
      extras.add(OTel.attributeInt('db.rows_affected', r.rowsAffected!));
    }
    if (r.insertId != null) {
      extras.add(OTel.attributeString('planetscale.insert_id', r.insertId!));
    }
    if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

String? _operationFromStatement(String statement) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
  const known = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'BEGIN',
    'COMMIT',
    'ROLLBACK',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'REPLACE',
  };
  return known.contains(first) ? first : null;
}
