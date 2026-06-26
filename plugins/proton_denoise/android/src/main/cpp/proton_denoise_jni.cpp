#include <jni.h>

#include <cstddef>

#include "proton_deepfilter_api.h"
#include "proton_dtln_api.h"
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
  return;
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
  return;
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

JNIEXPORT jfloat JNICALL
Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeProcessMonoInPlace(
    JNIEnv* env,
    jclass /*clazz*/,
    jlong handle,
    jfloatArray samples,
    jint offset,
    jint frame_size) {
  if (handle == 0 || samples == nullptr || frame_size <= 0 || offset < 0) {
    return 0.f;
  }
  const jsize array_len = env->GetArrayLength(samples);
  if (offset >= array_len) {
    return 0.f;
  }
  jfloat* data = env->GetFloatArrayElements(samples, nullptr);
  if (data == nullptr) {
    return 0.f;
  }
  const jsize available = array_len - offset;
  const size_t remaining = static_cast<size_t>(available);
  const float vad = proton_rnnoise_process_interleaved(
      FromHandle(handle), data + offset, remaining, 1);
  env->ReleaseFloatArrayElements(samples, data, 0);
  return vad;
}

JNIEXPORT jfloat JNICALL
Java_com_proton_proton_1denoise_ProtonRnnoiseNative_nativeProcessInterleavedAt(
    JNIEnv* env,
    jclass /*clazz*/,
    jlong handle,
    jobject buffer,
    jint float_offset,
    jint num_frames,
    jint num_channels) {
  if (handle == 0 || buffer == nullptr || num_frames <= 0 || num_channels <= 0 ||
      float_offset < 0) {
    return 0.f;
  }
  void* data = env->GetDirectBufferAddress(buffer);
  if (data == nullptr) {
    return 0.f;
  }
  const size_t sample_count =
      static_cast<size_t>(num_frames) * static_cast<size_t>(num_channels);
  const jlong capacity_bytes = env->GetDirectBufferCapacity(buffer);
  const jlong required_bytes = static_cast<jlong>(
      (static_cast<size_t>(float_offset) + sample_count) * sizeof(float));
  if (capacity_bytes < required_bytes) {
    return 0.f;
  }
  float* samples =
      static_cast<float*>(data) + static_cast<size_t>(float_offset);
  return proton_rnnoise_process_interleaved(
      FromHandle(handle), samples, sample_count, num_channels);
}

ProtonDtlnHandle* FromDtlnHandle(jlong handle) {
  return reinterpret_cast<ProtonDtlnHandle*>(handle);
}

JNIEXPORT jlong JNICALL
Java_com_proton_proton_1denoise_ProtonDtlnRsNative_nativeCreate(JNIEnv* /*env*/,
                                                                jclass /*clazz*/) {
  return reinterpret_cast<jlong>(proton_dtln_create());
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonDtlnRsNative_nativeDestroy(
    JNIEnv* /*env*/,
    jclass /*clazz*/,
    jlong handle) {
  proton_dtln_destroy(FromDtlnHandle(handle));
  return;
}

JNIEXPORT jint JNICALL
Java_com_proton_proton_1denoise_ProtonDtlnRsNative_nativeGetSampleRate(
    JNIEnv* /*env*/,
    jclass /*clazz*/) {
  return proton_dtln_get_sample_rate();
}

JNIEXPORT jint JNICALL
Java_com_proton_proton_1denoise_ProtonDtlnRsNative_nativeGetBlockShift(
    JNIEnv* /*env*/,
    jclass /*clazz*/) {
  return proton_dtln_get_block_shift();
}

JNIEXPORT jint JNICALL
Java_com_proton_proton_1denoise_ProtonDtlnRsNative_nativeDenoiseInterleaved(
    JNIEnv* env,
    jclass /*clazz*/,
    jlong handle,
    jobject buffer,
    jint sample_count) {
  if (handle == 0 || buffer == nullptr || sample_count <= 0) {
    return -1;
  }
  void* data = env->GetDirectBufferAddress(buffer);
  if (data == nullptr) {
    return -1;
  }
  const jlong capacity_bytes = env->GetDirectBufferCapacity(buffer);
  const jlong required_bytes =
      static_cast<jlong>(static_cast<size_t>(sample_count) * sizeof(float));
  if (capacity_bytes < required_bytes) {
    return -1;
  }
  return proton_dtln_denoise_interleaved(
      FromDtlnHandle(handle), static_cast<float*>(data),
      static_cast<size_t>(sample_count));
}

ProtonDeepFilterHandle* FromDeepFilterHandle(jlong handle) {
  return reinterpret_cast<ProtonDeepFilterHandle*>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeEnsureLoaded(
    JNIEnv* /*env*/,
    jclass /*clazz*/) {
  return proton_deepfilter_ensure_loaded() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeCreate(
    JNIEnv* env,
    jclass /*clazz*/,
    jstring model_path) {
  if (model_path == nullptr) {
    return 0;
  }
  const char* path = env->GetStringUTFChars(model_path, nullptr);
  if (path == nullptr) {
    return 0;
  }
  const jlong out =
      reinterpret_cast<jlong>(proton_deepfilter_create(path));
  env->ReleaseStringUTFChars(model_path, path);
  return out;
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
  proton_deepfilter_destroy(FromDeepFilterHandle(handle));
  return;
}

JNIEXPORT jint JNICALL
Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeGetFrameSize(
    JNIEnv* /*env*/,
    jclass /*clazz*/,
    jlong handle) {
  return proton_deepfilter_get_frame_size(FromDeepFilterHandle(handle));
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeSetEnabled(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jboolean enabled) {
  proton_deepfilter_set_enabled(FromDeepFilterHandle(handle), enabled ? 1 : 0);
  return;
}

// nosemgrep
JNIEXPORT void JNICALL Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeSetAttenLim(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jfloat lim_db) {
  proton_deepfilter_set_atten_lim(FromDeepFilterHandle(handle), lim_db);
  return;
}

JNIEXPORT jfloat JNICALL
Java_com_proton_proton_1denoise_ProtonDeepFilterNative_nativeProcessInterleavedAt(
    JNIEnv* env,
    jclass /*clazz*/,
    jlong handle,
    jobject buffer,
    jint float_offset,
    jint num_frames,
    jint num_channels) {
  if (handle == 0 || buffer == nullptr || num_frames <= 0 || num_channels <= 0 ||
      float_offset < 0) {
    return 0.f;
  }
  void* data = env->GetDirectBufferAddress(buffer);
  if (data == nullptr) {
    return 0.f;
  }
  const size_t sample_count =
      static_cast<size_t>(num_frames) * static_cast<size_t>(num_channels);
  const jlong capacity_bytes = env->GetDirectBufferCapacity(buffer);
  const jlong required_bytes = static_cast<jlong>(
      (static_cast<size_t>(float_offset) + sample_count) * sizeof(float));
  if (capacity_bytes < required_bytes) {
    return 0.f;
  }
  float* samples =
      static_cast<float*>(data) + static_cast<size_t>(float_offset);
  return proton_deepfilter_process_interleaved(
      FromDeepFilterHandle(handle), samples, sample_count, num_channels);
}

}  // extern "C"
