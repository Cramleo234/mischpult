// Atomare Lese-/Schreibzugriffe für den Ringpuffer zwischen zwei Echtzeit-Threads.
// (Swift bietet `Atomic` erst ab macOS 15; Mischpult läuft ab 14.2.)
#ifndef MISCHPULT_ATOMICS_H
#define MISCHPULT_ATOMICS_H

#include <stdatomic.h>
#include <stdint.h>

// Die Zeiger zeigen auf gewöhnliche, 8-Byte-ausgerichtete Zahlen; der Zugriff
// selbst ist atomar (Swift kann `_Atomic`-Typen nicht direkt verwenden).
static inline int64_t mp_load_acquire(int64_t *value) {
    return atomic_load_explicit((_Atomic int64_t *)value, memory_order_acquire);
}

static inline void mp_store_release(int64_t *value, int64_t newValue) {
    atomic_store_explicit((_Atomic int64_t *)value, newValue, memory_order_release);
}

#endif
