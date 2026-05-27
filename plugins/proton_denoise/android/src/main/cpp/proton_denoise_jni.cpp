#include <jni.h>

#include <cstddef>

#include "proton_rnnoise_api.h"

namespace {

ProtonRnnoiseHandle* FromHandle(jlong handle) {
  return reinterpret_cast<ProtonRnnoiseHandle*>(handle);
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeCreate(JNIEnv* /*env*/,
                                                               jclass /*clazz*/) {
  return reinterpret_cast<jlong>(proton_rnnoise_create());
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
  proton_rnnoise_destroy(FromHandle(handle));
}

JNIEXPORT jint JNICALL
Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeGetFrameSize(
    JNIEnv* /*env*/,
    jclass /*clazz*/) {
  return proton_rnnoise_get_frame_size();
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeSetEnabled(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jboolean enabled) {
  proton_rnnoise_set_enabled(FromHandle(handle), enabled ? 1 : 0);
}

JNIEXPORT jfloat JNICALL
Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeProcessInterleaved(
    JNIEnv* env,
    jclass /*clazz*/,
    jlong handle,
    jobject buffer,
    jint num_frames,
    jint num_channels) {
  if (handle == 0 || buffer == nullptr || num_frames <= 0 || num_channels <= 0) {
    return 0.f;
  }

  void* data = env->GetDirectBufferAddress(buffer);
  if (data == nullptr) {
    return 0.f;
  }

  const jlong capacity_bytes = env->GetDirectBufferCapacity(buffer);
  const size_t sample_count =
      static_cast<size_t>(num_frames) * static_cast<size_t>(num_channels);
  const jlong required_bytes =
      static_cast<jlong>(sample_count * sizeof(float));
  if (capacity_bytes < required_bytes) {
    return 0.f;
  }

  return proton_rnnoise_process_interleaved(
      FromHandle(handle), static_cast<float*>(data),
      sample_count, num_channels);
}

}  // extern "C"
