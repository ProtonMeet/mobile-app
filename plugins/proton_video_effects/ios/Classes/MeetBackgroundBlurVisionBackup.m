/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 *
 * Proton Meet is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Proton Meet is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Proton Meet. If not, see <https://www.gnu.org/licenses/>.
 */

#import "MeetBackgroundBlurVisionBackup.h"

#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>

#pragma mark - Vision + Core Image (backup)

static CGImagePropertyOrientation
MeetBackup_BackgroundBlurOrientationForRotationDegrees(int degrees) {
  switch (degrees) {
  case 90:
    return kCGImagePropertyOrientationRight;
  case 180:
    return kCGImagePropertyOrientationDown;
  case 270:
    return kCGImagePropertyOrientationLeft;
  case 0:
  default:
    return kCGImagePropertyOrientationUp;
  }
}

static BOOL MeetBackup_BackgroundBlurPixelFormatIsSupported(OSType fmt) {
  return fmt == kCVPixelFormatType_32BGRA ||
         fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
         fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
}

static CGColorSpaceRef MeetBackup_BackgroundBlurCreateRenderColorSpace(OSType fmt)
    CF_RETURNS_RETAINED {
  CGColorSpaceRef cs = NULL;
  if (fmt == kCVPixelFormatType_32BGRA) {
    cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  } else {
    cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
  }
  if (cs == NULL) {
    cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  }
  return cs;
}

void MeetBackgroundBlurApplyVisionPersonBlurIfPossible(
    CVPixelBufferRef pb, int rotationDegrees, CIContext *ciContext,
    VNGeneratePersonSegmentationRequest *segRequest) {
  if (pb == NULL || ciContext == NULL || segRequest == NULL) {
    return;
  }
  if (@available(iOS 15.0, *)) {
  } else {
    return;
  }

  OSType fmt = CVPixelBufferGetPixelFormatType(pb);
  if (!MeetBackup_BackgroundBlurPixelFormatIsSupported(fmt)) {
    return;
  }

  CGImagePropertyOrientation orient =
      MeetBackup_BackgroundBlurOrientationForRotationDegrees(rotationDegrees);
  NSError *error = nil;
  VNImageRequestHandler *handler =
      [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pb
                                             orientation:orient
                                                 options:@{}];
  if (![handler performRequests:@[ segRequest ] error:&error]) {
    return;
  }

  NSArray<VNObservation *> *results = segRequest.results;
  if (results.count == 0) {
    return;
  }
  VNPixelBufferObservation *observation =
      (VNPixelBufferObservation *)results.firstObject;
  if (![observation isKindOfClass:[VNPixelBufferObservation class]]) {
    return;
  }
  CVPixelBufferRef maskPB = observation.pixelBuffer;
  if (maskPB == NULL) {
    return;
  }

  CIImage *input = [CIImage imageWithCVPixelBuffer:pb];
  CIImage *mask = [CIImage imageWithCVPixelBuffer:maskPB];
  CGRect ire = input.extent;
  CGRect mre = mask.extent;
  if (mre.size.width < 1.0 || mre.size.height < 1.0 || ire.size.width < 1.0 ||
      ire.size.height < 1.0) {
    return;
  }

  CGFloat scaleX = ire.size.width / mre.size.width;
  CGFloat scaleY = ire.size.height / mre.size.height;
  CIImage *scaledMask = [[mask
      imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)]
      imageByCroppingToRect:ire];

  CIFilter *invert = [CIFilter filterWithName:@"CIColorInvert"];
  [invert setValue:scaledMask forKey:kCIInputImageKey];
  CIImage *blurWeight = invert.outputImage;

  CIFilter *blur = [CIFilter filterWithName:@"CIMaskedVariableBlur"];
  [blur setValue:input forKey:kCIInputImageKey];
  [blur setValue:blurWeight forKey:@"inputMask"];
  [blur setValue:@(20.0) forKey:kCIInputRadiusKey];
  CIImage *out = blur.outputImage;
  if (out == nil) {
    return;
  }
  out = [out imageByCroppingToRect:ire];

  CVReturn lock = CVPixelBufferLockBaseAddress(pb, 0);
  if (lock != kCVReturnSuccess) {
    return;
  }
  @try {
    CGColorSpaceRef cs = MeetBackup_BackgroundBlurCreateRenderColorSpace(fmt);
    if (cs != NULL) {
      [ciContext render:out toCVPixelBuffer:pb bounds:ire colorSpace:cs];
      CGColorSpaceRelease(cs);
    }
  } @finally {
    CVPixelBufferUnlockBaseAddress(pb, 0);
  }
}
