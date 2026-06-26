/// DeepFilterNet attenuation limit (`atten_lim` / `df_set_atten_lim`), in dB.
///
/// Lower values cap how aggressively noise is removed — usually better for voice
/// (less musical noise / less "underwater" artifacts). 100 dB ≈ unlimited (libDF
/// default before Meet tuning).
const double kDeepFilterDefaultAttenLimDb = 30;

/// Debug slider range (dB).
const double kDeepFilterMinAttenLimDb = 10;
const double kDeepFilterMaxAttenLimDb = 100;
