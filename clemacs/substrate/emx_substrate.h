#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EMX_SUBSTRATE_VERSION "0.1.0"

typedef uint64_t emx_value;

typedef int32_t emx_status;

enum
{
  EMX_STATUS_OK = 0,
  EMX_STATUS_QUIT = 2,
  EMX_STATUS_EINVAL = 22,
  EMX_STATUS_UNKNOWN = 1000,
};

const char *emx_substrate_version(void);
const char *emx_substrate_platform(void);

const char *emx_substrate_status_string(emx_status status);

emx_status emx_substrate_parse_int(const char *s, int32_t *out);

emx_status emx_tty_enter_raw(void);
emx_status emx_tty_exit_raw(void);
emx_status emx_tty_read_byte(uint8_t *out);
emx_status emx_tty_write(const uint8_t *buf, int32_t len);
emx_status emx_tty_get_winsize(int32_t *out_rows, int32_t *out_cols);

#ifdef __cplusplus
}
#endif
