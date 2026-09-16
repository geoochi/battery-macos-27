#pragma once
#include <stdbool.h>
// Force discharge is a one-time phase. Lid closure pauses it; reaching target ends it.
static bool shouldDischarge(bool pending, int percent, int target, bool lidOpen, bool adapterPresent, bool sleeping) {
 return pending && percent>target && lidOpen && adapterPresent && !sleeping;
}
