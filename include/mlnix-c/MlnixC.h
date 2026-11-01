/* The C surface of the mlnix dialects, for hosts that cannot link C++ (Kotlin/Native cinterop).
 * One session is one MLIRContext with the dialects mlnix-opt registers.  Text goes in, text comes out. */
#ifndef MLNIX_C_H
#define MLNIX_C_H
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MlnixSession MlnixSession;

MlnixSession *mlnixOpen(void);
void mlnixClose(MlnixSession *session);

/* Parses `text` as a module, verifies it and prints it as mlnix-opt does.  The result is malloc'd and NUL-ended, or
 * NULL when the text does not parse or verify: mlnixError then holds the diagnostics, valid until the next call. */
char *mlnixRoundTrip(MlnixSession *session, const char *text, size_t length);
const char *mlnixError(const MlnixSession *session);
void mlnixFree(char *text);

#ifdef __cplusplus
}
#endif
#endif
