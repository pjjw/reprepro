#ifndef REPREPRO_TRACKINGT_H
#define REPREPRO_TRACKINGT_H

enum filetype { ft_ALL_BINARY='a',
		ft_ARCH_BINARY='b',
		ft_CHANGES = 'c',
		ft_LOG='l',
		ft_SOURCE='s',
		ft_XTRA_DATA='x'};

struct trackedpackage {
	char *sourcename;
	char *sourceversion;
	struct strlist filekeys;
	int *refcounts;
	enum filetype *filetypes;
	struct {
		bool isnew:1;
		bool deleted:1;
	} flags;
};
typedef struct s_tracking *trackingdb;

struct trackingdata {
	/*@temp@*/trackingdb tracks;
	struct trackedpackage *pkg;
	/*@null@*/ struct trackingdata_remember {
		/*@null@*/struct trackingdata_remember *next;
		char *name;
		char *version;
	} *remembered;
};

struct distribution;
struct database;
typedef retvalue tracking_foreach_ro_action(struct distribution *, const struct trackedpackage *);
retvalue tracking_foreach_ro(struct database *, struct distribution *, tracking_foreach_ro_action *);
#endif /*REPREPRO_TRACKINGT_H*/
