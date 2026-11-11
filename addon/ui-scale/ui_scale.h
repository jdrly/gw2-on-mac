#pragma once
#include <windows.h>

/* Reads the ini, patches the critical section import (csspin=) and starts the worker thread
 * (from DllMain; the thread runs once the loader lock is free). */
void ui_scale_start(HINSTANCE self);
/* One line into gw2-ui-scale.log next to the DLL. */
void ui_log(const char *fmt, ...);
