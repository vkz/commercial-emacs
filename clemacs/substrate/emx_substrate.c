#include "emx_substrate.h"

#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

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

static bool emx_tty_saved = false;
static bool emx_tty_raw = false;
static struct termios emx_tty_orig;

emx_status emx_tty_enter_raw(void)
{
  if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO))
    return EMX_STATUS_EINVAL;

  if (emx_tty_raw)
    return EMX_STATUS_OK;

  if (!emx_tty_saved)
    {
      if (tcgetattr(STDIN_FILENO, &emx_tty_orig) != 0)
        return EMX_STATUS_EINVAL;
      emx_tty_saved = true;
    }

  struct termios raw = emx_tty_orig;
  cfmakeraw(&raw);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0)
    return EMX_STATUS_EINVAL;

  emx_tty_raw = true;
  return EMX_STATUS_OK;
}

emx_status emx_tty_exit_raw(void)
{
  if (!emx_tty_saved)
    return EMX_STATUS_OK;

  if (emx_tty_raw)
    {
      (void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &emx_tty_orig);
      emx_tty_raw = false;
    }

  return EMX_STATUS_OK;
}

emx_status emx_tty_read_byte(uint8_t *out)
{
  if (out == NULL)
    return EMX_STATUS_EINVAL;

  uint8_t b = 0;
  ssize_t n = read(STDIN_FILENO, &b, 1);
  if (n != 1)
    return EMX_STATUS_EINVAL;

  *out = b;
  return EMX_STATUS_OK;
}

emx_status emx_tty_write(const uint8_t *buf, int32_t len)
{
  if (buf == NULL || len < 0)
    return EMX_STATUS_EINVAL;

  const uint8_t *p = buf;
  int32_t remain = len;
  while (remain > 0)
    {
      ssize_t n = write(STDOUT_FILENO, p, (size_t)remain);
      if (n <= 0)
        return EMX_STATUS_EINVAL;
      p += n;
      remain -= (int32_t)n;
    }
  return EMX_STATUS_OK;
}

emx_status emx_tty_get_winsize(int32_t *out_rows, int32_t *out_cols)
{
  if (out_rows == NULL || out_cols == NULL)
    return EMX_STATUS_EINVAL;

  if (!isatty(STDOUT_FILENO))
    return EMX_STATUS_EINVAL;

  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) != 0)
    return EMX_STATUS_EINVAL;

  if (ws.ws_row == 0 || ws.ws_col == 0)
    return EMX_STATUS_EINVAL;

  *out_rows = (int32_t)ws.ws_row;
  *out_cols = (int32_t)ws.ws_col;
  return EMX_STATUS_OK;
}
