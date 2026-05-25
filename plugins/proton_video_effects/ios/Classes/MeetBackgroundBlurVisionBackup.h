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

#import <CoreVideo/CoreVideo.h>

@class CIContext;
@class VNGeneratePersonSegmentationRequest;

/// Vision + Core Image person segmentation and masked blur (backup implementation).
/// `rotationDegrees` must match WebRTC `RTCVideoRotation` (0, 90, 180, 270).
FOUNDATION_EXPORT void MeetBackgroundBlurApplyVisionPersonBlurIfPossible(
    CVPixelBufferRef _Nonnull pb, int rotationDegrees, CIContext *_Nonnull ciContext,
    VNGeneratePersonSegmentationRequest *_Nonnull segRequest);
