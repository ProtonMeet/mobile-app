package com.proton.proton_denoise

internal enum class DenoiseKind(val id: String) {
    RNNOISE("rnnoise"),
    DEEPFILTER("deepfilter"),
    DEEPFILTER2("deepfilter2"),
    DTLN_RS("dtln-rs"),
    ;

    companion object {
        fun fromId(id: String?): DenoiseKind? =
            entries.firstOrNull { it.id == id }
    }
}
