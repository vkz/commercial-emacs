#include "emx_substrate.h"

#include <errno.h>
#include <stdlib.h>

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

const char *emx_substrate_status_string(emx_status status)
{
  switch (status)
    {
    case EMX_STATUS_OK:
      return "ok";
    case EMX_STATUS_QUIT:
      return "quit";
    case EMX_STATUS_EINVAL:
      return "invalid argument";
    default:
      return "unknown error";
    }
}

emx_status emx_substrate_parse_int(const char *s, int32_t *out)
{
  if (s == NULL || out == NULL)
    return EMX_STATUS_EINVAL;

  errno = 0;
  char *end = NULL;
  long v = strtol(s, &end, 10);
  if (errno != 0)
    return EMX_STATUS_EINVAL;
  if (end == s)
    return EMX_STATUS_EINVAL;
  if (*end != '\0')
    return EMX_STATUS_EINVAL;
  if (v < INT32_MIN || v > INT32_MAX)
    return EMX_STATUS_EINVAL;

  *out = (int32_t)v;
  return EMX_STATUS_OK;
}
