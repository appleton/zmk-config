#pragma once
#include <stdbool.h>
struct device { bool ready; };
static inline bool device_is_ready(const struct device *dev) { return dev->ready; }
