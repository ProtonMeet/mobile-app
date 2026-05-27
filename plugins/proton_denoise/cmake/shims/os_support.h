/* Minimal os_support.h for building xiph/rnnoise without full autotools configure. */
#ifndef OS_SUPPORT_H
#define OS_SUPPORT_H

#include "common.h"

#ifndef OPUS_CLEAR
#define OPUS_CLEAR(dst, n) RNN_CLEAR(dst, n)
#endif

#endif /* OS_SUPPORT_H */
