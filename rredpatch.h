#ifndef REPREPRO_RREDPATCH_H
#define REPREPRO_RREDPATCH_H

#include "config.h"
#ifndef HAVE_GETLINE
ssize_t getline (char **lineptr, size_t *n, FILE *stream);
#endif

struct rred_patch;
struct modification;

retvalue patch_load(const char *, off_t, /*@out@*/struct rred_patch **);
retvalue patch_loadfd(const char *, int, off_t, /*@out@*/struct rred_patch **);
void patch_free(/*@only@*/struct rred_patch *);
/*@only@*//*@null@*/struct modification *patch_getmodifications(struct rred_patch *);
/*@null@*/const struct modification *patch_getconstmodifications(struct rred_patch *);
struct modification *modification_dup(const struct modification *);
void modification_freelist(/*@only@*/struct modification *);
retvalue combine_patches(/*@out@*/struct modification **, /*@only@*/struct modification *, /*@only@*/struct modification *);
void modification_printaspatch(void *, const struct modification *, void write_func(const void *, size_t, void *));
retvalue modification_addstuff(const char *source, struct modification **patch_p, /*@out@*/char **line_p);
retvalue patch_file(FILE *, const char *, const struct modification *);

#endif
