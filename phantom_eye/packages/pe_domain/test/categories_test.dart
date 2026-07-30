import 'dart:convert';
import 'dart:io';

import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

/// Cross-validates the ported category table and `matchCategory` against the
/// **real** `src/categories.ts`, compiled and executed by
/// `phantom_eye/tool/gen_category_fixture.mjs`.
///
/// This is stronger than the hand-written expectations elsewhere: there is no
/// second copy of the category data to drift. Editing a keyword list in
/// TypeScript fails this test until the Dart side is regenerated.
Map<String, dynamic> _loadFixture() {
  final path =
      Platform.environment['PE_CATEGORY_FIXTURE'] ??
      'test/fixtures/category_reference.json';
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final fixture = _loadFixture();

  group('parity with src/categories.ts', () {
    test('the default pin colour matches', () {
      expect(kDefaultPinColorHex, fixture['defaultPinColorHex']);
    });

    test('every category matches in order, field by field', () {
      final expected = (fixture['categories'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        kCategories.length,
        expected.length,
        reason: 'category count must match',
      );

      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = kCategories[i];
        final where = 'category $i (${want['id']})';

        expect(got.id, want['id'], reason: '$where id');
        expect(got.label, want['label'], reason: '$where label');
        expect(got.colorHex, want['colorHex'], reason: '$where colour');
        expect(
          got.osmTags.map((t) => t.toString()).toList(),
          (want['osmTags'] as List).cast<String>(),
          reason: '$where OSM tags',
        );
        expect(
          got.keywords,
          (want['keywords'] as List).cast<String>(),
          reason: '$where keywords',
        );
      }
    });

    test('matchCategory agrees on every probe', () {
      final probes = (fixture['matches'] as List).cast<Map<String, dynamic>>();
      expect(probes, isNotEmpty);
      for (final probe in probes) {
        final query = probe['q'] as String;
        final wantId = probe['id'] as String?;
        expect(
          matchCategory(query)?.id,
          wantId,
          reason: 'matchCategory(${jsonEncode(query)})',
        );
      }
    });
  });

  group('categoryById', () {
    test('finds each declared category', () {
      for (final c in kCategories) {
        expect(categoryById(c.id)?.id, c.id);
      }
    });

    test('null, empty and unknown ids yield null', () {
      expect(categoryById(null), isNull);
      expect(categoryById(''), isNull);
      expect(categoryById('nope'), isNull);
    });
  });

  group('normalizeCategoryQuery', () {
    test('lowercases and collapses whitespace', () {
      expect(normalizeCategoryQuery('  FOOD   Court '), 'food court');
    });

    test('strips filler words', () {
      expect(normalizeCategoryQuery('best coffee near me'), 'coffee');
      expect(normalizeCategoryQuery('the closest gas'), 'gas');
      expect(normalizeCategoryQuery('some places to eat'), 'to eat');
    });

    test('strips digits and punctuation but keeps accented letters', () {
      expect(normalizeCategoryQuery('76 gas'), 'gas');
      expect(normalizeCategoryQuery('7-eleven'), 'eleven');
      expect(normalizeCategoryQuery('café!'), 'café');
    });

    test('a query of only filler or symbols normalises to empty', () {
      expect(normalizeCategoryQuery('!!!'), isEmpty);
      expect(normalizeCategoryQuery('123'), isEmpty);
      expect(normalizeCategoryQuery('   '), isEmpty);
    });
  });

  group('matchCategory behaviour worth naming', () {
    test('multi-word keywords need the whole-phrase pass', () {
      // Reachable only because the phrase itself is a keyword; no single
      // token of "gas station" other than "gas" would do it.
      expect(matchCategory('gas station')?.id, 'gas');
      expect(matchCategory('ski resort')?.id, 'ski');
      expect(matchCategory('driving range')?.id, 'golf');
    });

    test('"food store" resolves to groceries, not food', () {
      // The whole-phrase pass scans in declaration order, and "food store" is
      // a groceries keyword while Food has no such keyword — so groceries
      // wins despite the word "food" appearing first.
      expect(matchCategory('food store')?.id, 'groceries');
    });

    test(
      'the three-token cap keeps long place names out of category search',
      () {
        // Four tokens after normalisation: falls through to geocoding even
        // though "coffee" is present.
        expect(matchCategory('coffee shop downtown seattle'), isNull);
        // Three tokens still matches.
        expect(matchCategory('good coffee shop')?.id, 'coffee');
      },
    );

    test('digit stripping still lets a brand-prefixed query match', () {
      expect(
        matchCategory('76 gas')?.id,
        'gas',
        reason: 'digits are dropped, leaving "gas"',
      );
    });

    test('specific place names fall through', () {
      for (final q in ['starbucks', 'wilderness', 'nearest atm', '7-eleven']) {
        expect(matchCategory(q), isNull, reason: q);
      }
    });

    test('case is irrelevant', () {
      expect(matchCategory('FOOD')?.id, 'food');
      expect(matchCategory('Food')?.id, 'food');
    });
  });
}
