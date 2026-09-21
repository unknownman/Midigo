import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_contract.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';

void main() {
  final EvaluationContract contract = EvaluationContract.instance;

  test('T1 - identity: mvp_default_v1 / v1.1 and Evaluation Contract v1.1 are '
      'materialized', () {
    expect(EvaluationContract.contractName, 'Evaluation Contract');
    expect(EvaluationContract.contractVersion, 'v1.1');
    expect(EvaluationContract.profileId, 'mvp_default_v1');
    expect(EvaluationContract.profileVersion, 'v1.1');
    expect(contract.identity.status, ContractRuleStatus.defined);
    expect(contract.profile.status, ContractRuleStatus.defined);
  });

  test('T2 - block applicability follows the locked profile exactly', () {
    const enabled = <EvaluationDimension>{
      EvaluationDimension.pitch,
      EvaluationDimension.timing,
      EvaluationDimension.simultaneity,
      EvaluationDimension.retrievalLatency,
    };
    for (final dimension in EvaluationDimension.values) {
      final rule = contract.byDimension[dimension]!.applicability(
        TargetMode.block,
      );
      expect(
        rule.status,
        enabled.contains(dimension)
            ? ContractRuleStatus.defined
            : ContractRuleStatus.derived,
        reason: 'block applicability of $dimension',
      );
      expect(
        MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
          TargetMode.block,
          dimension,
        ),
        rule.status == ContractRuleStatus.defined,
        reason: 'block applicability of $dimension must mirror the profile',
      );
    }
  });

  test('T3 - arpeggio applicability follows the locked profile exactly', () {
    const enabled = <EvaluationDimension>{
      EvaluationDimension.pitch,
      EvaluationDimension.timing,
      EvaluationDimension.order,
      EvaluationDimension.ioi,
      EvaluationDimension.retrievalLatency,
    };
    for (final dimension in EvaluationDimension.values) {
      final rule = contract.byDimension[dimension]!.applicability(
        TargetMode.arpeggio,
      );
      expect(
        rule.status,
        enabled.contains(dimension)
            ? ContractRuleStatus.defined
            : ContractRuleStatus.derived,
        reason: 'arpeggio applicability of $dimension',
      );
      expect(
        MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
          TargetMode.arpeggio,
          dimension,
        ),
        rule.status == ContractRuleStatus.defined,
        reason: 'arpeggio applicability of $dimension must mirror the profile',
      );
    }
  });

  test('T4 - no invented policy: every policy slot is unresolved and holds no '
      'value', () {
    expect(contract.policySnapshot.hasAnyDefinedPolicies, isFalse);
    for (final dimension in contract.dimensions) {
      expect(dimension.threshold.status, ContractRuleStatus.unresolved);
      expect(
        dimension.threshold.contractValueMs,
        isNull,
        reason: 'threshold of $dimension',
      );
      expect(dimension.threshold.unresolvedReason, isNotNull);
    }
    final counted =
        contract.definedRuleCount +
        contract.derivedRuleCount +
        contract.unresolvedRuleCount;
    expect(counted, contract.allRules.length);
  });

  test(
    'T5 - diagnostic isolation: H2.2 diagnostics are not evaluation policy',
    () {
      expect(contract.diagnosticsIsolation.status, ContractRuleStatus.defined);
      final sources = contract.diagnosticNonPolicySources.join('\n');
      expect(sources, contains('60 ms'));
      expect(sources, contains('5 ms'));
      expect(sources, contains('simultaneityWindowMs'));
      for (final dimension in contract.dimensions) {
        expect(
          dimension.threshold.contractValueMs,
          isNull,
          reason: 'threshold of $dimension must carry no diagnostic value',
        );
      }
      expect(contract.policySnapshot.hasAnyDefinedPolicies, isFalse);
    },
  );

  test('T6 - retrieval latency: runtime-anchor absence stays explicit', () {
    expect(
      EvaluationContract.retrievalLatencyUnavailableReason,
      'NO_RUNTIME_PERFORMANCE_ANCHOR',
    );
    expect(
      contract.retrievalLatencyRuntimeState.status,
      ContractRuleStatus.defined,
    );
    expect(contract.retrievalLatencyRuntimeState.note, contains('anchor'));
    final retrieval =
        contract.byDimension[EvaluationDimension.retrievalLatency]!;
    expect(
      retrieval.applicability(TargetMode.block).status,
      ContractRuleStatus.defined,
    );
    expect(
      retrieval.applicability(TargetMode.arpeggio).status,
      ContractRuleStatus.defined,
    );
    expect(retrieval.unavailableBehavior.status, ContractRuleStatus.unresolved);
    expect(contract.policySnapshot.retrievalLatencyMs, isNull);
  });

  test('T7 - determinism: identical repository conditions yield identical '
      'contract projections', () {
    final EvaluationContract other = EvaluationContract.build();
    expect(identical(other, contract), isFalse);
    expect(other == contract, isTrue);
    expect(other.hashCode, contract.hashCode);
    expect(other.toMap(), contract.toMap());
  });

  test('T8 - immutability: contract collections cannot mutate after '
      'construction', () {
    expect(
      () => (contract.dimensions as dynamic).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (contract.diagnosticNonPolicySources as dynamic).clear(),
      throwsUnsupportedError,
    );
    final applicability = contract.dimensions.first.applicabilityMap;
    expect(() => (applicability as dynamic).clear(), throwsUnsupportedError);
  });

  test('T9 - provenance: every DEFINED/DERIVED rule carries a repository '
      'source; every UNRESOLVED rule states why', () {
    expect(contract.definedRuleCount, greaterThan(0));
    expect(contract.derivedRuleCount, greaterThan(0));
    expect(contract.unresolvedRuleCount, greaterThan(0));
    for (final rule in contract.allRules) {
      if (rule.isResolved) {
        final provenance = rule.provenance;
        expect(provenance, isNotNull, reason: 'resolved ${rule.section}');
        expect(provenance!.sourceKind, isNotEmpty);
        expect(provenance.sourcePath, isNotEmpty);
        expect(provenance.sourceIdentifier, isNotEmpty);
        expect(rule.unresolvedReason, isNull);
      }
      if (rule.isUnresolved) {
        expect(
          rule.unresolvedReason,
          isNotNull,
          reason: 'unresolved ${rule.section}',
        );
        expect(rule.unresolvedReason!.isEmpty, isFalse);
      }
    }
  });

  test('T10 - partial contract safety: unresolved rules cannot be represented '
      'as executable policy', () {
    expect(contract.containsExecutablePolicy, isFalse);
    for (final rule in contract.allRules) {
      if (rule.isUnresolved) {
        expect(rule.contractValueMs, isNull);
        expect(rule.provenance, isNull);
      }
    }
    expect(contract.policySnapshot.hasAnyDefinedPolicies, isFalse);
    expect(
      contract.unresolvedRuleCount,
      greaterThan(0),
      reason: 'the materialized contract is intentionally partial',
    );
  });
}
