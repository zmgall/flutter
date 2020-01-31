// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart';

/// Compares image pixels against a golden image file.
///
/// Instances of this comparator will be used as the backend for
/// [matchesGoldenFile].
///
/// Instances of this comparator will be invoked by the test framework in the
/// [TestWidgetsFlutterBinding.runAsync] zone and are thus not subject to the
/// fake async constraints that are normally imposed on widget tests (i.e. the
/// need or the ability to call [WidgetTester.pump] to advance the microtask
/// queue).
///
/// ## What is Golden File Testing?
///
/// The term __golden file__ refers to a master image that is considered the true
/// rendering of a given widget, state, application, or other visual
/// representation you have chosen to capture.
///
/// By keeping a master reference of visual aspects of your application, you can
/// prevent unintended changes as you develop by testing against them.
///
/// Here, a minor code change has altered the appearance of a widget. A golden
/// file test has compared the image generated at the time of the test to the
/// golden master file that was generated earlier. The test has identified the
/// change, preventing unintended modifications.
///
/// |  Sample                        |  Image |
/// |--------------------------------|--------|
/// |  Golden Master Image           | ![A golden master image](https://flutter.github.io/assets-for-api-docs/assets/flutter-test/goldens/widget_masterImage.png)  |
/// |  Difference                    | ![The pixel difference](https://flutter.github.io/assets-for-api-docs/assets/flutter-test/goldens/widget_isolatedDiff.png)  |
/// |  Test image after modification | ![Test image](https://flutter.github.io/assets-for-api-docs/assets/flutter-test/goldens/widget_testImage.png) |
///
/// See also:
///
///  * [LocalFileComparator] for the default [GoldenFileComparator]
///    implementation for `flutter test`.
///  * [matchesGoldenFile], the function from [flutter_test] that invokes the
///    comparator.
abstract class GoldenFileComparator {
  /// Compares the pixels of decoded png [imageBytes] against the golden file
  /// identified by [golden].
  ///
  /// The returned future completes with a boolean value that indicates whether
  /// the pixels decoded from [imageBytes] match the golden file's pixels.
  ///
  /// In the case of comparison mismatch, the comparator may choose to throw a
  /// [TestFailure] if it wants to control the failure message, often in the
  /// form of a [ComparisonResult] that provides detailed information about the
  /// mismatch.
  ///
  /// The method by which [golden] is located and by which its bytes are loaded
  /// is left up to the implementation class. For instance, some implementations
  /// may load files from the local file system, whereas others may load files
  /// over the network or from a remote repository.
  Future<bool> compare(Uint8List imageBytes, Uri golden);

  /// Updates the golden file identified by [golden] with [imageBytes].
  ///
  /// This will be invoked in lieu of [compare] when [autoUpdateGoldenFiles]
  /// is `true` (which gets set automatically by the test framework when the
  /// user runs `flutter test --update-goldens`).
  ///
  /// The method by which [golden] is located and by which its bytes are written
  /// is left up to the implementation class.
  Future<void> update(Uri golden, Uint8List imageBytes);

  /// Returns a new golden file [Uri] to incorporate any [version] number with
  /// the [key].
  ///
  /// The [version] is an optional int that can be used to differentiate
  /// historical golden files.
  ///
  /// Version numbers are used in golden file tests for package:flutter. You can
  /// learn more about these tests [here](https://github.com/flutter/flutter/wiki/Writing-a-golden-file-test-for-package:flutter).
  Uri getTestUri(Uri key, int version) {
    if (version == null)
      return key;
    final String keyString = key.toString();
    final String extension = path.extension(keyString);
    return Uri.parse(
      keyString
        .split(extension)
        .join() + '.' + version.toString() + extension
    );
  }

  /// Returns a [ComparisonResult] to describe the pixel differential of the
  /// [test] and [master] image bytes provided.
  static ComparisonResult compareLists(List<int> test, List<int> master) {
    if (identical(test, master))
      return ComparisonResult(passed: true);

    if (test == null || master == null || test.isEmpty || master.isEmpty) {
      return ComparisonResult(
        passed: false,
        error: 'Pixel test failed, null image provided.',
      );
    }

    final Image testImage = decodePng(test);
    final Image masterImage = decodePng(master);

    assert(testImage != null);
    assert(masterImage != null);

    final int width = testImage.width;
    final int height = testImage.height;

    if (width != masterImage.width || height != masterImage.height) {
      return ComparisonResult(
        passed: false,
        error: 'Pixel test failed, image sizes do not match.\n'
          'Master Image: ${masterImage.width} X ${masterImage.height}\n'
          'Test Image: ${testImage.width} X ${testImage.height}',
      );
    }

    int pixelDiffCount = 0;
    final int totalPixels = width * height;
    final Image invertedMaster = invert(Image.from(masterImage));
    final Image invertedTest = invert(Image.from(testImage));

    final Map<String, Image> diffs = <String, Image>{
      'masterImage' : masterImage,
      'testImage' : testImage,
      'maskedDiff' : Image.from(testImage),
      'isolatedDiff' : Image(width, height),
    };

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int testPixel = testImage.getPixel(x, y);
        final int masterPixel = masterImage.getPixel(x, y);

        final int diffPixel = (getRed(testPixel) - getRed(masterPixel)).abs()
          + (getGreen(testPixel) - getGreen(masterPixel)).abs()
          + (getBlue(testPixel) - getBlue(masterPixel)).abs()
          + (getAlpha(testPixel) - getAlpha(masterPixel)).abs();

        if (diffPixel != 0 ) {
          final int invertedMasterPixel = invertedMaster.getPixel(x, y);
          final int invertedTestPixel = invertedTest.getPixel(x, y);
          final int maskPixel = math.max(invertedMasterPixel, invertedTestPixel);
          diffs['maskedDiff'].setPixel(x, y, maskPixel);
          diffs['isolatedDiff'].setPixel(x, y, maskPixel);
          pixelDiffCount++;
        }
      }
    }

    if (pixelDiffCount > 0) {
      return ComparisonResult(
        passed: false,
        error: 'Pixel test failed, '
          '${((pixelDiffCount/totalPixels) * 100).toStringAsFixed(2)}% '
          'diff detected.',
        diffs: diffs,
      );
    }
    return ComparisonResult(passed: true);
  }
}

/// Compares pixels against those of a golden image file.
///
/// This comparator is used as the backend for [matchesGoldenFile].
///
/// When using `flutter test`, a comparator implemented by [LocalFileComparator]
/// is used if no other comparator is specified. It treats the golden key as
/// a relative path from the test file's directory. It will then load the
/// golden file's bytes from disk and perform a pixel-for-pixel comparison of
/// the decoded PNGs, returning true only if there's an exact match.
///
/// When using `flutter test --update-goldens`, the [LocalFileComparator]
/// updates the files on disk to match the rendering.
///
/// When using `flutter run`, the default comparator ([TrivialComparator])
/// is used. It prints a message to the console but otherwise does nothing. This
/// allows tests to be developed visually on a real device.
///
/// Callers may choose to override the default comparator by setting this to a
/// custom comparator during test set-up (or using directory-level test
/// configuration). For example, some projects may wish to install a comparator
/// with tolerance levels for allowable differences.
///
/// See also:
///
///  * [flutter_test] for more information about how to configure tests at the
///    directory-level.
GoldenFileComparator get goldenFileComparator => _goldenFileComparator;
GoldenFileComparator _goldenFileComparator = const TrivialComparator._();
set goldenFileComparator(GoldenFileComparator value) {
  assert(value != null);
  _goldenFileComparator = value;
}

/// Whether golden files should be automatically updated during tests rather
/// than compared to the image bytes recorded by the tests.
///
/// When this is `true`, [matchesGoldenFile] will always report a successful
/// match, because the bytes being tested implicitly become the new golden.
///
/// The Flutter tool will automatically set this to `true` when the user runs
/// `flutter test --update-goldens`, so callers should generally never have to
/// explicitly modify this value.
///
/// See also:
///
///   * [goldenFileComparator]
bool autoUpdateGoldenFiles = false;

/// Placeholder comparator that is set as the value of [goldenFileComparator]
/// when the initialization that happens in the test bootstrap either has not
/// yet happened or has been bypassed.
///
/// The test bootstrap file that gets generated by the Flutter tool when the
/// user runs `flutter test` is expected to set [goldenFileComparator] to
/// a comparator that resolves golden file references relative to the test
/// directory. From there, the caller may choose to override the comparator by
/// setting it to another value during test initialization. The only case
/// where we expect it to remain uninitialized is when the user runs a test
/// via `flutter run`. In this case, the [compare] method will just print a
/// message that it would have otherwise run a real comparison, and it will
/// return trivial success.
///
/// This class can't be constructed. It represents the default value of
/// [goldenFileComparator].
class TrivialComparator implements GoldenFileComparator {
  const TrivialComparator._();

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) {
    print('Golden file comparison requested for "$golden"; skipping...');
    return Future<bool>.value(true);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) {
    throw StateError('goldenFileComparator has not been initialized');
  }

  @override
  Uri getTestUri(Uri key, int version) {
    return key;
  }
}

/// The result of a pixel comparison test.
///
/// The [ComparisonResult] will always indicate if a test has [passed]. The
/// optional [error] and [diffs] parameters provide further information about
/// the result of a failing test.
class ComparisonResult {
  /// Creates a new [ComparisonResult] for the current test.
  ComparisonResult({
    @required this.passed,
    this.error,
    this.diffs,
  }) : assert(passed != null);

  /// Indicates whether or not a pixel comparison test has failed.
  ///
  /// This value cannot be null.
  final bool passed;

  /// Error message used to describe the cause of the pixel comparison failure.
  final String error;

  /// Map containing differential images to illustrate found variants in pixel
  /// values in the execution of the pixel test.
  // TODO(jonahwilliams): fix type signature when image is updated to support web.
  final Map<String, Object> diffs;
}
