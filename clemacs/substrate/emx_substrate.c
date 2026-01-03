#include "emx_substrate.h"

#if defined(__APPLE__) && defined(__MACH__)
#define EMX_PLATFORM "darwin"
#elif defined(__linux__)
#define EMX_PLATFORM "gnu-linux"
#elif defined(__FreeBSD__)
#define EMX_PLATFORM "freebsd"
#else
#define EMX_PLATFORM "unknown"
#endif

const char *emx_substrate_version(void) { return EMX_SUBSTRATE_VERSION; }

const char *emx_substrate_platform(void) { return EMX_PLATFORM; }
