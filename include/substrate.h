#ifndef SUBSTRATE_H_
#define SUBSTRATE_H_

#include <mach-o/loader.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

void MSHookFunction(void *symbol, void *replace, void **result);

#ifdef __cplusplus
}
#endif

#endif // SUBSTRATE_H_
