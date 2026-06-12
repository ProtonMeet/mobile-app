#include "proton_deepfilter_api.h"

#include <cstdio>
#include <dlfcn.h>

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <memory>
#include <mutex>

namespace {

using DFState = struct DFState;

using DfCreateFn = DFState* (*)(const char*, float, const char*);
using DfFreeFn = void (*)(DFState*);
using DfGetFrameLengthFn = size_t (*)(DFState*);
using DfProcessFrameFn = float (*)(DFState*, float*, float*);
using DfSetAttenLimFn = void (*)(DFState*, float);

DfCreateFn g_df_create = nullptr;
DfFreeFn g_df_free = nullptr;
DfGetFrameLengthFn g_df_get_frame_length = nullptr;
DfProcessFrameFn g_df_process_frame = nullptr;
DfSetAttenLimFn g_df_set_atten_lim = nullptr;

void* g_deepfilter_handle = nullptr;
std::once_flag g_load_once;
bool g_symbols_ready = false;

bool ResolveSymbol(void* handle, const char* name, void** out) {
  if (handle == nullptr || name == nullptr || out == nullptr) {
    return false;
  }
  dlerror();
  void* sym = dlsym(handle, name);
  const char* err = dlerror();
  if (sym == nullptr || err != nullptr) {
    return false;
  }
  *out = sym;
  return true;
}

bool ResolveAllSymbols(void* handle) {
  return ResolveSymbol(handle, "df_create",
                       reinterpret_cast<void**>(&g_df_create)) &&
         ResolveSymbol(handle, "df_free",
                       reinterpret_cast<void**>(&g_df_free)) &&
         ResolveSymbol(handle, "df_get_frame_length",
                       reinterpret_cast<void**>(&g_df_get_frame_length)) &&
         ResolveSymbol(handle, "df_process_frame",
                       reinterpret_cast<void**>(&g_df_process_frame)) &&
         ResolveSymbol(handle, "df_set_atten_lim",
                       reinterpret_cast<void**>(&g_df_set_atten_lim));
}

void LoadDeepFilterOnce() {
  if (ResolveAllSymbols(RTLD_DEFAULT)) {
    g_symbols_ready = true;
    return;
  }

  // nosemgrep
  g_deepfilter_handle = dlopen("libdeepfilter.so", RTLD_NOW | RTLD_LOCAL);
  if (g_deepfilter_handle != nullptr &&
      ResolveAllSymbols(g_deepfilter_handle)) {
    g_symbols_ready = true;
  }
}

template <size_t kChannels>
float ProcessInterleavedFixed(DFState* state, size_t frame_size, float* samples,
                              size_t sample_count) {
  constexpr size_t channels = kChannels;
  if (state == nullptr || g_df_process_frame == nullptr || frame_size == 0 ||
      sample_count % channels != 0) {
    return 0.f;
  }

  const size_t samples_per_channel = sample_count / channels;
  float snr = 0.f;

  for (size_t ch = 0; ch < channels; ++ch) {
    float in_frame[512];
    float out_frame[512];
    if (frame_size > sizeof(in_frame) / sizeof(in_frame[0])) {
      return snr;
    }

    if (samples_per_channel == frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[i * channels + ch];
      }
      snr = g_df_process_frame(state, in_frame, out_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[i * channels + ch] = out_frame[i];
      }
      continue;
    }

    for (size_t frame_start = 0; frame_start + frame_size <= samples_per_channel;
         frame_start += frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[(frame_start + i) * channels + ch];
      }
      snr = g_df_process_frame(state, in_frame, out_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[(frame_start + i) * channels + ch] = out_frame[i];
      }
    }
  }

  return snr;
}

}  // namespace

struct ProtonDeepFilterHandle {
  DFState* state;
  size_t frame_size;
  bool enabled;
};

extern "C" {

int proton_deepfilter_ensure_loaded() {
  std::call_once(g_load_once, LoadDeepFilterOnce);
  return g_symbols_ready ? 1 : 0;
}

bool ModelPathLooksLikeGzip(const char* model_path) {
  if (model_path == nullptr || model_path[0] == '\0') {
    return false;
  }
  FILE* file = std::fopen(model_path, "rb");
  if (file == nullptr) {
    return false;
  }
  unsigned char header[2] = {};
  const size_t want = sizeof(header);
  const bool read_ok = std::fread(header, 1, want, file) == want;
  std::fclose(file);
  return read_ok && header[0] == 0x1f && header[1] == 0x8b;
}

ProtonDeepFilterHandle* proton_deepfilter_create(const char* model_path) {
  if (!proton_deepfilter_ensure_loaded() || g_df_create == nullptr ||
      g_df_get_frame_length == nullptr || g_df_free == nullptr ||
      model_path == nullptr || model_path[0] == '\0') {
    return nullptr;
  }
  if (!ModelPathLooksLikeGzip(model_path)) {
    return nullptr;
  }

  DFState* state = g_df_create(model_path, 100.f, nullptr);
  if (state == nullptr) {
    return nullptr;
  }

  const size_t frame_size = g_df_get_frame_length(state);
  if (frame_size == 0) {
    g_df_free(state);
    return nullptr;
  }

  return new ProtonDeepFilterHandle{state, frame_size, false};
}

void proton_deepfilter_destroy(ProtonDeepFilterHandle* handle) {
  if (handle == nullptr) {
    return;
  }
  std::unique_ptr<ProtonDeepFilterHandle> owned(handle);
  if (owned->state != nullptr && g_df_free != nullptr) {
    g_df_free(owned->state);
    owned->state = nullptr;
  }
}

int proton_deepfilter_get_frame_size(ProtonDeepFilterHandle* handle) {
  if (handle == nullptr) {
    return 0;
  }
  return static_cast<int>(handle->frame_size);
}

void proton_deepfilter_set_enabled(ProtonDeepFilterHandle* handle, int enabled) {
  if (handle != nullptr) {
    handle->enabled = enabled != 0;
  }
}

int proton_deepfilter_is_enabled(ProtonDeepFilterHandle* handle) {
  return handle != nullptr && handle->enabled ? 1 : 0;
}

void proton_deepfilter_set_atten_lim(ProtonDeepFilterHandle* handle, float lim_db) {
  if (handle != nullptr && handle->state != nullptr && g_df_set_atten_lim != nullptr) {
    g_df_set_atten_lim(handle->state, lim_db);
  }
}

float proton_deepfilter_process_interleaved(ProtonDeepFilterHandle* handle,
                                            float* samples, size_t sample_count,
                                            int num_channels) {
  if (handle == nullptr || handle->state == nullptr || !handle->enabled ||
      samples == nullptr || sample_count == 0 || num_channels <= 0) {
    return 0.f;
  }

  if (num_channels == 1) {
    return ProcessInterleavedFixed<1>(handle->state, handle->frame_size, samples,
                                      sample_count);
  }
  if (num_channels == 2) {
    return ProcessInterleavedFixed<2>(handle->state, handle->frame_size, samples,
                                      sample_count);
  }
  return 0.f;
}

}  // extern "C"
