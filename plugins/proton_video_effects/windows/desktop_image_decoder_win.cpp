/*
 * Copyright (c) 2026 Proton AG
 * Windows implementation of the shared image decoder, backed by WIC.
 * The interface and every caller live in common/desktop.
 */

#include <windows.h>
#include <wincodec.h>

#include <utility>
#include <vector>

#include "desktop_image_decoder.h"

namespace meet_video_effects {
namespace {

/** Minimal COM handle: these decodes are linear, so a full smart pointer is overkill. */
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() {
    if (ptr_) ptr_->Release();
  }
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  T** Receive() { return &ptr_; }
  void** ReceiveVoid() { return reinterpret_cast<void**>(&ptr_); }
  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }

 private:
  T* ptr_ = nullptr;
};

/**
 * WIC needs COM on the calling thread. Flutter's platform thread may not have
 * initialised it, and per-decode init is cheap next to decoding an image.
 */
class ComScope {
 public:
  ComScope() {
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    // RPC_E_CHANGED_MODE: the thread already lives in another apartment, which
    // still lets WIC run — we just must not tear that apartment down.
    owns_ = SUCCEEDED(hr);
  }
  ~ComScope() {
    if (owns_) CoUninitialize();
  }
  ComScope(const ComScope&) = delete;
  ComScope& operator=(const ComScope&) = delete;

 private:
  bool owns_ = false;
};

/** EXIF orientation tag (0x0112); absent or unreadable means "upright". */
WICBitmapTransformOptions ReadExifTransform(IWICBitmapFrameDecode* frame) {
  ComPtr<IWICMetadataQueryReader> reader;
  if (FAILED(frame->GetMetadataQueryReader(reader.Receive())) || !reader) {
    return WICBitmapTransformRotate0;
  }
  PROPVARIANT value;
  PropVariantInit(&value);
  // JPEG stores it under /app1/ifd; PNG and friends simply have no match.
  HRESULT hr = reader->GetMetadataByName(L"/app1/ifd/{ushort=274}", &value);
  if (FAILED(hr)) {
    hr = reader->GetMetadataByName(L"/ifd/{ushort=274}", &value);
  }
  unsigned short orientation = 1;
  if (SUCCEEDED(hr) && value.vt == VT_UI2) {
    orientation = value.uiVal;
  }
  PropVariantClear(&value);

  switch (orientation) {
    case 2:
      return WICBitmapTransformFlipHorizontal;
    case 3:
      return WICBitmapTransformRotate180;
    case 4:
      return WICBitmapTransformFlipVertical;
    case 5:
      return static_cast<WICBitmapTransformOptions>(
          WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal);
    case 6:
      return WICBitmapTransformRotate90;
    case 7:
      return static_cast<WICBitmapTransformOptions>(
          WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal);
    case 8:
      return WICBitmapTransformRotate270;
    default:
      return WICBitmapTransformRotate0;
  }
}

DecodedImage DecodeFrame(IWICImagingFactory* factory,
                         IWICBitmapFrameDecode* frame) {
  DecodedImage image;

  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(converter.Receive()))) {
    return image;
  }
  if (FAILED(converter->Initialize(frame, GUID_WICPixelFormat32bppRGBA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return image;
  }

  // Keep the converter alive: the rotator only wraps it, it does not copy.
  IWICBitmapSource* source = converter.Get();
  ComPtr<IWICBitmapFlipRotator> rotator;
  const WICBitmapTransformOptions transform = ReadExifTransform(frame);
  if (transform != WICBitmapTransformRotate0 &&
      SUCCEEDED(factory->CreateBitmapFlipRotator(rotator.Receive())) &&
      SUCCEEDED(rotator->Initialize(converter.Get(), transform))) {
    source = rotator.Get();
  }

  UINT width = 0;
  UINT height = 0;
  if (FAILED(source->GetSize(&width, &height)) || width == 0 || height == 0) {
    return image;
  }

  const UINT stride = width * 4;
  std::vector<uint8_t> pixels(static_cast<size_t>(stride) * height);
  if (FAILED(source->CopyPixels(nullptr, stride,
                                static_cast<UINT>(pixels.size()),
                                pixels.data()))) {
    return image;
  }

  image.width = static_cast<int>(width);
  image.height = static_cast<int>(height);
  image.rgba = std::move(pixels);
  return image;
}

}  // namespace

DecodedImage DecodeImageFile(const std::string& path) {
  DecodedImage image;
  if (path.empty()) return image;

  const int wide_len =
      MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
  if (wide_len <= 0) return image;
  std::wstring wide_path(static_cast<size_t>(wide_len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wide_path.data(), wide_len);
  wide_path.resize(static_cast<size_t>(wide_len) - 1);  // drop the NUL

  ComScope com;
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_IWICImagingFactory,
                              factory.ReceiveVoid())) ||
      !factory) {
    return image;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromFilename(
          wide_path.c_str(), nullptr, GENERIC_READ,
          WICDecodeMetadataCacheOnDemand, decoder.Receive()))) {
    return image;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, frame.Receive()))) {
    return image;
  }
  return DecodeFrame(factory.Get(), frame.Get());
}

DecodedImage DecodeImageBytes(const uint8_t* data, size_t size) {
  DecodedImage image;
  if (!data || size == 0) return image;

  ComScope com;
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_IWICImagingFactory,
                              factory.ReceiveVoid())) ||
      !factory) {
    return image;
  }

  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(stream.Receive())) ||
      FAILED(stream->InitializeFromMemory(const_cast<BYTE*>(data),
                                          static_cast<DWORD>(size)))) {
    return image;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                              WICDecodeMetadataCacheOnDemand,
                                              decoder.Receive()))) {
    return image;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, frame.Receive()))) {
    return image;
  }
  return DecodeFrame(factory.Get(), frame.Get());
}

}  // namespace meet_video_effects
