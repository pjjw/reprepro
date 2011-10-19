/*  This file is part of "reprepro"
 *  Copyright (C) 2007,2008 Bernhard R. Link
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2 as
 *  published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02111-1301  USA
 */
#include <config.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <assert.h>
#include <limits.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <db.h>

#include "globals.h"
#include "error.h"
#include "ignore.h"
#include "strlist.h"
#include "names.h"
#include "database.h"
#include "dirs.h"
#include "filecntl.h"
#include "files.h"
#include "filelist.h"
#include "reference.h"
#include "tracking.h"
#include "dpkgversions.h"
#include "distribution.h"
#include "database_p.h"

#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)
#define LIBDB_VERSION_STRING "bdb" TOSTRING(DB_VERSION_MAJOR) "." TOSTRING(DB_VERSION_MINOR) "." TOSTRING(DB_VERSION_PATCH)
#define CLEARDBT(dbt) { memset(&dbt, 0, sizeof(dbt)); }
#define SETDBT(dbt, datastr) {const char *my = datastr; memset(&dbt, 0, sizeof(dbt)); dbt.data = (void *)my; dbt.size = strlen(my) + 1;}
#define SETDBTl(dbt, datastr, datasize) {const char *my = datastr; memset(&dbt, 0, sizeof(dbt)); dbt.data = (void *)my; dbt.size = datasize;}

static void database_free(/*@only@*/ struct database *db) {
	if( db == NULL )
		return;
	free(db->version);
	free(db->lastsupportedversion);
	free(db->dbversion);
	free(db->lastsupporteddbversion);
	free(db);
}

static inline char *dbfilename(const char *filename) {
	return calc_dirconcat(global.dbdir, filename);
}

/**********************/
/* lock file handling */
/**********************/

static retvalue database_lock(struct database *db, size_t waitforlock) {
	char *lockfile;
	int fd;
	retvalue r;
	size_t tries = 0;

	assert( !db->locked );
	db->dircreationdepth = 0;
	r = dir_create_needed(global.dbdir, &db->dircreationdepth);
	if( RET_WAS_ERROR(r) )
		return r;

	lockfile = dbfilename("lockfile");
	if( lockfile == NULL )
		return RET_ERROR_OOM;
	fd = open(lockfile,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_NOCTTY,S_IRUSR|S_IWUSR);
	while( fd < 0 ) {
		int e = errno;
		if( e == EEXIST ) {
			if( tries < waitforlock && ! interrupted() ) {
				unsigned int timetosleep = 10;
				if( verbose >= 0 )
					printf("Could not aquire lock: %s already exists!\nWaiting 10 seconds before trying again.\n", lockfile);
				while( timetosleep > 0 )
					timetosleep = sleep(timetosleep);
				tries++;
				fd = open(lockfile,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_NOCTTY,S_IRUSR|S_IWUSR);
				continue;

			}
			fprintf(stderr,
"The lock file '%s' already exists. There might be another instance with the\n"
"same database dir running. To avoid locking overhead, only one process\n"
"can access the database at the same time. Do not delete the lock file unless\n"
"you are sure no other version is still running!\n", lockfile);

		} else
			fprintf(stderr, "Error %d creating lock file '%s': %s!\n",
					e, lockfile, strerror(e));
		free(lockfile);
		return RET_ERRNO(e);
	}
	// TODO: do some more locking of this file to avoid problems
	// with the non-atomity of O_EXCL with nfs-filesystems...
	if( close(fd) != 0 ) {
		int e = errno;
		fprintf(stderr, "(Late) Error %d creating lock file '%s': %s!\n",
				e, lockfile, strerror(e));
		(void)unlink(lockfile);
		free(lockfile);
		return RET_ERRNO(e);
	}
	free(lockfile);
	db->locked = true;
	return RET_OK;
}

static void releaselock(struct database *db) {
	char *lockfile;

	assert( db->locked );

	lockfile = dbfilename("lockfile");
	if( lockfile == NULL )
		return;
	if( unlink(lockfile) != 0 ) {
		int e = errno;
		fprintf(stderr, "Error %d deleting lock file '%s': %s!\n",
				e, lockfile, strerror(e));
		(void)unlink(lockfile);
	}
	free(lockfile);
	dir_remove_new(global.dbdir, db->dircreationdepth);
	db->locked = false;
}

static retvalue writeversionfile(struct database *);

retvalue database_close(struct database *db) {
	retvalue result = RET_OK, r;

	if( db->references != NULL) {
		r = table_close(db->references);
		RET_UPDATE(result, r);
		db->references = NULL;
	}
	if( db->checksums != NULL ) {
		r = table_close(db->checksums);
		RET_UPDATE(result, r);
		db->checksums = NULL;
	}
	if( db->contents != NULL ) {
		r = table_close(db->contents);
		RET_UPDATE(result, r);
		db->contents = NULL;
	}
	r = writeversionfile(db);
	RET_UPDATE(result, r);
	if( db->locked )
		releaselock(db);
	database_free(db);
	return result;
}

static retvalue database_hasdatabasefile(UNUSED(const struct database *database), const char *filename, /*@out@*/bool *exists_p) {
	char *fullfilename;

	fullfilename = dbfilename(filename);
	if( fullfilename == NULL )
		return RET_ERROR_OOM;
	*exists_p = isregularfile(fullfilename);
	free(fullfilename);
	return RET_OK;
}

enum database_type {
	dbt_QUERY,
	dbt_BTREE, dbt_BTREEDUP, dbt_BTREEPAIRS,
	dbt_HASH,
	dbt_COUNT /* must be last */
};
static const uint32_t types[dbt_COUNT] = {
	DB_UNKNOWN,
	DB_BTREE, DB_BTREE, DB_BTREE,
	DB_HASH
};

static int paireddatacompare(UNUSED(DB *db), const DBT *a, const DBT *b);

static retvalue database_opentable(UNUSED(struct database *database), const char *filename, /*@null@*/const char *subtable, enum database_type type, uint32_t flags, /*@out@*/DB **result) {
	char *fullfilename;
	DB *table;
	int dbret;

	fullfilename = dbfilename(filename);
	if( fullfilename == NULL )
		return RET_ERROR_OOM;

	dbret = db_create(&table, NULL, 0);
	if ( dbret != 0) {
		fprintf(stderr, "db_create: %s\n", db_strerror(dbret));
		free(fullfilename);
		return RET_DBERR(dbret);
	}
	if( type == dbt_BTREEDUP || type == dbt_BTREEPAIRS ) {
		dbret = table->set_flags(table, DB_DUPSORT);
		if( dbret != 0 ) {
			table->err(table, dbret, "db_set_flags(DB_DUPSORT):");
			(void)table->close(table, 0);
			free(fullfilename);
			return RET_DBERR(dbret);
		}
	}
	if( type == dbt_BTREEPAIRS ) {
		dbret = table->set_dup_compare(table,  paireddatacompare);
		if( dbret != 0 ) {
			table->err(table, dbret, "db_set_dup_compare:");
			(void)table->close(table, 0);
			free(fullfilename);
			return RET_DBERR(dbret);
		}
	}

#if DB_VERSION_MAJOR == 4
#define DB_OPEN(database,filename,name,type,flags) database->open(database,NULL,filename,name,type,flags,0664)
#else
#if DB_VERSION_MAJOR == 3
#define DB_OPEN(database,filename,name,type,flags) database->open(database,filename,name,type,flags,0664)
#else
#error Unexpected DB_VERSION_MAJOR!
#endif
#endif
	dbret = DB_OPEN(table, fullfilename, subtable, types[type], flags);
	if( dbret == ENOENT && !ISSET(flags, DB_CREATE) ) {
		(void)table->close(table, 0);
		free(fullfilename);
		return RET_NOTHING;
	}
	if (dbret != 0) {
		if( subtable != NULL )
			table->err(table, dbret, "db_open(%s:%s)[%d]",
					fullfilename, subtable, dbret);
		else
			table->err(table, dbret, "db_open(%s)[%d]",
					fullfilename, dbret);
		(void)table->close(table, 0);
		free(fullfilename);
		return RET_DBERR(dbret);
	}
	free(fullfilename);
	*result = table;
	return RET_OK;
}

retvalue database_listsubtables(struct database *database,const char *filename,struct strlist *result) {
	DB *table;
	DBC *cursor;
	DBT key,data;
	int dbret;
	retvalue ret,r;
	struct strlist ids;

	r = database_opentable(database, filename, NULL,
			dbt_QUERY, DB_RDONLY, &table);
	if( !RET_IS_OK(r) )
		return r;

	cursor = NULL;
	if( (dbret = table->cursor(table, NULL, &cursor, 0)) != 0 ) {
		table->err(table, dbret, "cursor(%s):", filename);
		(void)table->close(table,0);
		return RET_ERROR;
	}
	CLEARDBT(key);
	CLEARDBT(data);

	strlist_init(&ids);

	ret = RET_NOTHING;
	while( (dbret=cursor->c_get(cursor,&key,&data,DB_NEXT)) == 0 ) {
		char *identifier = strndup(key.data, key.size);
		if( identifier == NULL ) {
			(void)table->close(table, 0);
			strlist_done(&ids);
			return RET_ERROR_OOM;
		}
		r = strlist_add(&ids, identifier);
		if( RET_WAS_ERROR(r) ) {
			(void)table->close(table, 0);
			strlist_done(&ids);
			return r;
		}
		CLEARDBT(key);
		CLEARDBT(data);
	}

	if( dbret != 0 && dbret != DB_NOTFOUND ) {
		table->err(table, dbret, "c_get(%s):", filename);
		(void)table->close(table, 0);
		strlist_done(&ids);
		return RET_DBERR(dbret);
	}
	if( (dbret = cursor->c_close(cursor)) != 0 ) {
		table->err(table, dbret, "c_close(%s):", filename);
		(void)table->close(table, 0);
		strlist_done(&ids);
		return RET_DBERR(dbret);
	}

	dbret = table->close(table, 0);
	if( dbret != 0 ) {
		table->err(table, dbret, "close(%s):", filename);
		strlist_done(&ids);
		return RET_DBERR(dbret);
	} else {
		strlist_move(result, &ids);
		return RET_OK;
	}
}

retvalue database_dropsubtable(UNUSED(struct database *database), const char *table, const char *subtable) {
	char *filename;
	DB *db;
	int dbret;

	filename = dbfilename(table);
	if( filename == NULL )
		return RET_ERROR_OOM;

	if ((dbret = db_create(&db, NULL, 0)) != 0) {
		fprintf(stderr, "db_create: %s %s\n", filename, db_strerror(dbret));
		free(filename);
		return RET_DBERR(dbret);
	}
	dbret = db->remove(db, filename, subtable, 0);
	if( dbret == ENOENT ) {
		free(filename);
		return RET_NOTHING;
	}
	if (dbret != 0) {
		fprintf(stderr,"Error removing '%s' from %s!\n",
				subtable, filename);
		free(filename);
		return RET_DBERR(dbret);
	}

	free(filename);
	return RET_OK;
}

static inline bool targetisdefined(const char *identifier, struct distribution *distributions) {
	struct distribution *d;
	struct target *t;

	for( d = distributions ; d != NULL ; d = d->next ) {
		for( t = d->targets; t != NULL ; t = t->next ) {
			if( strcmp(t->identifier, identifier) == 0 ) {
				t->existed = true;
				return true;
			}
		}
	}
	return false;
}

static retvalue warnidentifers(struct database *db, const struct strlist *identifiers, struct distribution *distributions, bool readonly) {
	struct distribution *d;
	struct target *t;
	const char *identifier;
	retvalue r;
	int i;

	for( i = 0; i < identifiers->count ; i++ ) {
		identifier = identifiers->values[i];

		if( targetisdefined(identifier, distributions) )
			continue;

		fprintf(stderr,
"Error: packages database contains unused '%s' database.\n", identifier);
		if( ignored[IGN_undefinedtarget] == 0 ) {
			(void)fputs(
"This either means you removed a distribution, component or architecture from\n"
"the distributions config file without calling clearvanished, or your config\n"
"does not belong to this database.\n",
					stderr);
		}
		if( IGNORABLE(undefinedtarget) ) {
			(void)fputs("Ignoring as --ignore=undefinedtarget given.\n",
					stderr);
			ignored[IGN_undefinedtarget]++;
			continue;
		}

		(void)fputs("To ignore use --ignore=undefinedtarget.\n", stderr);
		return RET_ERROR;
	}
	if( readonly )
		return RET_OK;
	for( d = distributions ; d != NULL ; d = d->next ) {
		bool architecture_existed[d->architectures.count];
		bool have_old = false;

		/* check for new architectures */
		memset(architecture_existed, 0, sizeof(architecture_existed));

		for( t = d->targets; t != NULL ; t = t->next ) {
			int o;

			if( !t->existed )
				continue;

			o = atomlist_ofs(&d->architectures,
					t->architecture_atom);
			assert( o >= 0 );
			if( o >= 0 ) {
				architecture_existed[o] = true;
				/* only warn about new ones if there
				 * is at least one old one, otherwise
				 * it's just a new distribution */
				have_old = true;
			}
		}
		for( i = 0 ; have_old && i < d->architectures.count ; i++ ) {
			architecture_t a;

			if( architecture_existed[i] )
				continue;

			a = d->architectures.atoms[i];

			fprintf(stderr,
"New architecture '%s' in '%s'. Perhaps you want to call\n"
"reprepro flood '%s' '%s'\n"
"to populate it with architecture 'all' packages from other architectures.\n",
				atoms_architectures[a], d->codename,
				d->codename, atoms_architectures[a]);
		}

		/* create databases, so we know next time what is new */
		for( t = d->targets; t != NULL ; t = t->next ) {
			if( t->existed )
				continue;
			/* create database now, to test it can be created
			 * early, and to know when new architectures
			 * arrive in the future. */
			r = target_initpackagesdb(t, db, READWRITE);
			if( RET_WAS_ERROR(r) )
				return r;
			r = target_closepackagesdb(t);
			if( RET_WAS_ERROR(r) )
				return r;
		}
	}
	return RET_OK;
}

static retvalue warnunusedtracking(const struct strlist *codenames, const struct distribution *distributions) {
	const char *codename;
	const struct distribution *d;
	int i;

	for( i = 0; i < codenames->count ; i++ ) {
		codename = codenames->values[i];

		d = distributions;
		while( d != NULL && strcmp(d->codename, codename) != 0 )
			d = d->next;
		if( d != NULL && d->tracking != dt_NONE )
			continue;

		fprintf(stderr,
"Error: tracking database contains unused '%s' database.\n", codename);
		if( ignored[IGN_undefinedtracking] == 0 ) {
			if( d == NULL )
				(void)fputs(
"This either means you removed a distribution from the distributions config\n"
"file without calling clearvanished (or at least removealltracks), you\n"
"experienced a bug in retrack in versions < 3.0.0, you found a new bug or your\n"
"config does not belong to this database.\n",
						stderr);
			else
				(void)fputs(
"This either means you removed the Tracking: options from this distribution without\n"
"calling removealltracks for it, or your config does not belong to this database.\n",
						stderr);
		}
		if( IGNORABLE(undefinedtracking) ) {
			(void)fputs("Ignoring as --ignore=undefinedtracking given.\n",
					stderr);
			ignored[IGN_undefinedtracking]++;
			continue;
		}

		(void)fputs("To ignore use --ignore=undefinedtracking.\n", stderr);
		return RET_ERROR;
	}
	return RET_OK;
}

static retvalue readline(/*@out@*/char **result, FILE *f, const char *versionfilename) {
	char buffer[21];
	size_t l;

	if( fgets(buffer, 20, f) == NULL ) {
		int e = errno;
		if( e == 0 ) {
			fprintf(stderr, "Error reading '%s': unexpected empty file\n",
					versionfilename);
			return RET_ERROR;
		} else {
			fprintf(stderr, "Error reading '%s': %s(errno is %d)\n",
					versionfilename, strerror(e), e);
			return RET_ERRNO(e);
		}
	}
	l = strlen(buffer);
	while( l > 0 && ( buffer[l-1] == '\r' || buffer[l-1] == '\n' ) ) {
		buffer[--l] = '\0';
	}
	if( l == 0 ) {
		fprintf(stderr, "Error reading '%s': unexpcted empty line.\n",
				versionfilename);
		return RET_ERROR;
	}
	*result = strdup(buffer);
	if( *result == NULL )
		return RET_ERROR_OOM;
	return RET_OK;
}

static retvalue readversionfile(struct database *db, bool nopackagesyet) {
	char *versionfilename;
	FILE *f;
	retvalue r;
	int c;

	versionfilename = dbfilename("version");
	if( versionfilename == NULL )
		return RET_ERROR_OOM;
	f = fopen(versionfilename, "r");
	if( f == NULL ) {
		int e = errno;

		if( e != ENOENT ) {
			fprintf(stderr, "Error opening '%s': %s(errno is %d)\n",
					versionfilename, strerror(e), e);
			free(versionfilename);
			return RET_ERRNO(e);
		}
		free(versionfilename);
		if( nopackagesyet ) {
			/* set to default for new packages.db files: */
			db->version = strdup(VERSION);
			if( db->version == NULL )
				return RET_ERROR_OOM;
			db->capabilities.createnewtables = true;
		} else
			db->version = NULL;
		db->lastsupportedversion = NULL;
		db->dbversion = NULL;
		db->lastsupporteddbversion = NULL;
		return RET_NOTHING;
	}
	/* first line is the version creating this database */
	r = readline(&db->version, f, versionfilename);
	if( RET_WAS_ERROR(r) ) {
		(void)fclose(f);
		free(versionfilename);
		return r;
	}
	/* second line says which versions of reprepro will be able to cope
	 * with this database */
	r = readline(&db->lastsupportedversion, f, versionfilename);
	if( RET_WAS_ERROR(r) ) {
		(void)fclose(f);
		free(versionfilename);
		return r;
	}
	/* next line is the version of the underlying database library */
	r = readline(&db->dbversion, f, versionfilename);
	if( RET_WAS_ERROR(r) ) {
		(void)fclose(f);
		free(versionfilename);
		return r;
	}
	/* and then the minimum version of this library needed. */
	r = readline(&db->lastsupporteddbversion, f, versionfilename);
	if( RET_WAS_ERROR(r) ) {
		(void)fclose(f);
		free(versionfilename);
		return r;
	}
	(void)fclose(f);
	free(versionfilename);

	/* check for enabled capabilities in the version */

	r = dpkgversions_cmp(db->version, "3", &c);
	if( RET_WAS_ERROR(r) )
		return r;
	if( c >= 0 )
		db->capabilities.createnewtables = true;

	/* ensure we can understand it */

	r = dpkgversions_cmp(VERSION, db->lastsupportedversion, &c);
	if( RET_WAS_ERROR(r) )
		return r;
	if( c < 0 ) {
		fprintf(stderr,
"According to %s/version this database was created with a future version\n"
"and uses features this version cannot understand. Aborting...\n",
				global.dbdir);
		return RET_ERROR;
	}

	/* ensure it's a libdb database: */

	if( strncmp(db->dbversion, "bdb", 3) != 0 ) {
		fprintf(stderr,
"According to %s/version this database was created with a yet unsupported\n"
"database library. Aborting...\n",
				global.dbdir);
		return RET_ERROR;
	}
	if( strncmp(db->lastsupporteddbversion, "bdb", 3) != 0 ) {
		fprintf(stderr,
"According to %s/version this database was created with a yet unsupported\n"
"database library. Aborting...\n",
				global.dbdir);
		return RET_ERROR;
	}
	r = dpkgversions_cmp(LIBDB_VERSION_STRING, db->lastsupporteddbversion, &c);
	if( RET_WAS_ERROR(r) )
		return r;
	if( c < 0 ) {
		fprintf(stderr,
"According to %s/version this database was created with a future version\n"
"%s of libdb. The libdb version this binary is linked against cannot yet\n"
"handle this format. Aborting...\n",
				global.dbdir, db->dbversion+3);
		return RET_ERROR;
	}
	return RET_OK;
}

static retvalue writeversionfile(struct database *db) {
	char *versionfilename, *finalversionfilename;
	FILE *f;
	int i, e;

	versionfilename = dbfilename("version.new");
	if( versionfilename == NULL )
		return RET_ERROR_OOM;
	f = fopen(versionfilename, "w");
	if( f == NULL ) {
		e = errno;
		fprintf(stderr, "Error creating '%s': %s(errno is %d)\n",
					versionfilename, strerror(e), e);
		free(versionfilename);
		return RET_ERRNO(e);
	}
	if( db->version == NULL )
		(void)fputs("0\n", f);
	else {
		(void)fputs(db->version, f);
		(void)fputc('\n', f);
	}
	if( db->lastsupportedversion == NULL ) {
		(void)fputs("3.3.0\n", f);
	} else {
		int c;
		retvalue r;

		r = dpkgversions_cmp(db->lastsupportedversion, "3.3.0", &c);
		if( !RET_IS_OK(r) || c < 0 )
			(void)fputs("3.3.0\n", f);
		else {
			(void)fputs(db->lastsupportedversion, f);
			(void)fputc('\n', f);
		}
	}
	if( db->dbversion == NULL )
		fprintf(f, "bdb%d.%d.%d\n", DB_VERSION_MAJOR, DB_VERSION_MINOR, DB_VERSION_PATCH);
	else {
		(void)fputs(db->dbversion, f);
		(void)fputc('\n', f);
	}
	if( db->lastsupporteddbversion == NULL )
		fprintf(f, "bdb%d.%d.0\n", DB_VERSION_MAJOR, DB_VERSION_MINOR);
	else {
		(void)fputs(db->lastsupporteddbversion, f);
		(void)fputc('\n', f);
	}

	e = ferror(f);

	if( e != 0 ) {
		fprintf(stderr, "Error writing '%s': %s(errno is %d)\n",
				versionfilename, strerror(e), e);
		(void)fclose(f);
		unlink(versionfilename);
		free(versionfilename);
		return RET_ERRNO(e);
	}
	if( fclose(f) != 0 ) {
		e = errno;
		fprintf(stderr, "Error writing '%s': %s(errno is %d)\n",
				versionfilename, strerror(e), e);
		unlink(versionfilename);
		free(versionfilename);
		return RET_ERRNO(e);
	}
	finalversionfilename = dbfilename("version");
	if( finalversionfilename == NULL ) {
		unlink(versionfilename);
		free(versionfilename);
		return RET_ERROR_OOM;
	}

	i = rename(versionfilename, finalversionfilename);
	if( i != 0 ) {
		e = errno;
		fprintf(stderr, "Error %d moving '%s' to '%s': %s\n",
				e, versionfilename, finalversionfilename,
				strerror(e));
		(void)unlink(versionfilename);
		free(versionfilename);
		free(finalversionfilename);
		return RET_ERRNO(e);
	}
	free(finalversionfilename);
	free(versionfilename);
	return RET_OK;
}

static retvalue createnewdatabase(struct database *db, struct distribution *distributions) {
	struct distribution *d;
	struct target *t;
	retvalue result = RET_NOTHING, r;

	for( d = distributions ; d != NULL ; d = d->next ) {
		for( t = d->targets ; t != NULL ; t = t->next ) {
			r = target_initpackagesdb(t, db, READWRITE);
			RET_UPDATE(result, r);
			if( RET_IS_OK(r) ) {
				r = target_closepackagesdb(t);
				RET_UPDATE(result, r);
			}
		}
	}
	r = writeversionfile(db);
	RET_UPDATE(result, r);
	return result;
}

/* Initialize a database.
 * - if not fast, make all kind of checks for consistency (TO BE IMPLEMENTED),
 * - if readonly, do not create but return with RET_NOTHING
 * - lock database, waiting a given amount of time if already locked
 */
retvalue database_create(struct database **result, struct distribution *alldistributions, bool fast, bool nopackages, bool allowunused, bool readonly, size_t waitforlock, bool verbosedb) {
	struct database *n;
	retvalue r;
	bool packagesfileexists, trackingfileexists, nopackagesyet;

	if( readonly && !isdir(global.dbdir) ) {
		if( verbose >= 0 )
			fprintf(stderr, "Exiting without doing anything, as there is no database yet that could result in other actions.\n");
		return RET_NOTHING;
	}

	n = calloc(1, sizeof(struct database));
	if( n == NULL )
		return RET_ERROR_OOM;

	r = database_lock(n, waitforlock);
	assert( r != RET_NOTHING );
	if( !RET_IS_OK(r) ) {
		database_free(n);
		return r;
	}
	n->readonly = readonly;
	n->verbose = verbosedb;

	r = database_hasdatabasefile(n, "packages.db", &packagesfileexists);
	if( RET_WAS_ERROR(r) )
		return r;
	r = database_hasdatabasefile(n, "tracking.db", &trackingfileexists);
	if( RET_WAS_ERROR(r) )
		return r;

	nopackagesyet = !packagesfileexists && !trackingfileexists;

	r = readversionfile(n, nopackagesyet);
	if( RET_WAS_ERROR(r) ) {
		releaselock(n);
		database_free(n);
		return r;
	}

	if( nopackages ) {
		n->nopackages = true;
		*result = n;
		return RET_OK;
	}

	if( nopackagesyet ) {
		// TODO: handle readonly, but only once packages files may no
		// longer be generated when it is active...

		r = createnewdatabase(n, alldistributions);
		if( RET_WAS_ERROR(r) ) {
			releaselock(n);
			database_free(n);
			return r;
		}
	}

	/* from now on we should call database_close, as other stuff was handled,
	 * so writing the version file cannot harm (and not doing so could) */

	if( !allowunused && !fast && packagesfileexists )  {
		struct strlist identifiers;

		r = database_listpackages(n, &identifiers);
		if( RET_WAS_ERROR(r) ) {
			database_close(n);
			return r;
		}
		if( RET_IS_OK(r) ) {
			r = warnidentifers(n, &identifiers,
					alldistributions, readonly);
			if( RET_WAS_ERROR(r) ) {
				strlist_done(&identifiers);
				database_close(n);
				return r;
			}
			strlist_done(&identifiers);
		}
	}
	if( !allowunused && !fast && trackingfileexists )  {
		struct strlist codenames;

		r = tracking_listdistributions(n, &codenames);
		if( RET_WAS_ERROR(r) ) {
			database_close(n);
			return r;
		}
		if( RET_IS_OK(r) ) {
			r = warnunusedtracking(&codenames, alldistributions);
			if( RET_WAS_ERROR(r) ) {
				strlist_done(&codenames);
				database_close(n);
				return r;
			}
			strlist_done(&codenames);
		}
	}

	*result = n;
	return RET_OK;
}

/********************************************************************************
 * Stuff string parts                                                           *
 ********************************************************************************/

static const char databaseerror[] = "Internal error of the underlying BerkeleyDB database:\n";

/********************************************************************************
 * Stuff to handle data in tables                                               *
 ********************************************************************************
 There is nothing that connot be solved by another layer of indirection, except
 too many levels of indirection. (Source forgotten) */

struct table {
	char *name, *subname;
	DB *berkeleydb;
	bool *flagreset;
	bool readonly, verbose;
};

static void table_printerror(struct table *table, int dbret, const char *action) {
	if( table->subname != NULL )
		table->berkeleydb->err(table->berkeleydb, dbret,
				"%sWithin %s subtable %s at %s",
				databaseerror, table->name, table->subname,
				action);
	else
		table->berkeleydb->err(table->berkeleydb, dbret,
				"%sWithin %s at %s",
				databaseerror, table->name, action);
}

retvalue table_close(struct table *table) {
	int dbret;
	retvalue result;

	if( table == NULL )
		return RET_NOTHING;
	if( table->flagreset != NULL )
		*table->flagreset = false;
	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		dbret = 0;
	} else
		dbret = table->berkeleydb->close(table->berkeleydb, 0);
	if( dbret != 0 ) {
		fprintf(stderr, "db_close(%s, %s): %s\n",
				table->name, table->subname,
				db_strerror(dbret));
		result = RET_DBERR(dbret);
	} else
		result = RET_OK;
	free(table->name);
	free(table->subname);
	free(table);
	return result;
}

retvalue table_getrecord(struct table *table, const char *key, char **data_p) {
	int dbret;
	DBT Key, Data;

	assert( table != NULL );
	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		return RET_NOTHING;
	}

	SETDBT(Key, key);
	CLEARDBT(Data);
	Data.flags = DB_DBT_MALLOC;

	dbret = table->berkeleydb->get(table->berkeleydb, NULL,
			&Key, &Data, 0);
	// TODO: find out what error code means out of memory...
	if( dbret == DB_NOTFOUND )
		return RET_NOTHING;
	if( dbret != 0 ) {
		table_printerror(table, dbret, "get");
		return RET_DBERR(dbret);
	}
	if( Data.data == NULL )
		return RET_ERROR_OOM;
	if( Data.size <= 0 ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not null-terminated) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not null-terminated) data!",
					table->name);
		free(Data.data);
		return RET_ERROR;
	}
	*data_p = Data.data;
	return RET_OK;
}

retvalue table_getpair(struct table *table, const char *key, const char *value, /*@out@*/const char **data_p, /*@out@*/size_t *datalen_p) {
	int dbret;
	DBT Key, Data;
	size_t valuelen = strlen(value);

	assert( table != NULL );
	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		return RET_NOTHING;
	}

	SETDBT(Key, key);
	SETDBTl(Data, value, valuelen + 1);

	dbret = table->berkeleydb->get(table->berkeleydb, NULL,
			&Key, &Data, DB_GET_BOTH);
	if( dbret == DB_NOTFOUND || dbret == DB_KEYEMPTY )
		return RET_NOTHING;
	if( dbret != 0 ) {
		table_printerror(table, dbret, "get(BOTH)");
		return RET_DBERR(dbret);
	}
	if( Data.data == NULL )
		return RET_ERROR_OOM;
	if( Data.size < valuelen + 2  ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not paired) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not paired) data!",
					table->name);
		return RET_ERROR;
	}
	*data_p = ((const char*)Data.data) + valuelen + 1;
	*datalen_p = Data.size - valuelen - 2;
	return RET_OK;
}

retvalue table_gettemprecord(struct table *table, const char *key, const char **data_p, size_t *datalen_p) {
	int dbret;
	DBT Key, Data;

	assert( table != NULL );
	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		return RET_NOTHING;
	}

	SETDBT(Key, key);
	CLEARDBT(Data);

	dbret = table->berkeleydb->get(table->berkeleydb, NULL,
			&Key, &Data, 0);
	// TODO: find out what error code means out of memory...
	if( dbret == DB_NOTFOUND )
		return RET_NOTHING;
	if( dbret != 0 ) {
		table_printerror(table, dbret, "get");
		return RET_DBERR(dbret);
	}
	if( Data.data == NULL )
		return RET_ERROR_OOM;
	if( data_p == NULL ) {
		assert( datalen_p == NULL );
		return RET_OK;
	}
	if( Data.size <= 0 ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not null-terminated) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not null-terminated) data!",
					table->name);
		return RET_ERROR;
	}
	*data_p = Data.data;
	if( datalen_p != NULL )
		*datalen_p = Data.size - 1;
	return RET_OK;
}

retvalue table_checkrecord(struct table *table, const char *key, const char *data) {
	int dbret;
	DBT Key, Data;
	DBC *cursor;
	retvalue r;

	SETDBT(Key, key);
	SETDBT(Data, data);
	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL, &cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		return RET_DBERR(dbret);
	}
	dbret=cursor->c_get(cursor, &Key, &Data, DB_GET_BOTH);
	if( dbret == 0 ) {
		r = RET_OK;
	} else if( dbret == DB_NOTFOUND ) {
		r = RET_NOTHING;
	} else {
		table_printerror(table, dbret, "c_get");
		(void)cursor->c_close(cursor);
		return RET_DBERR(dbret);
	}
	dbret = cursor->c_close(cursor);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_close");
		return RET_DBERR(dbret);
	}
	return r;
}

retvalue table_removerecord(struct table *table, const char *key, const char *data) {
	int dbret;
	DBT Key, Data;
	DBC *cursor;
	retvalue r;

	SETDBT(Key, key);
	SETDBT(Data, data);
	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL, &cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		return RET_DBERR(dbret);
	}
	dbret=cursor->c_get(cursor, &Key, &Data, DB_GET_BOTH);

	if( dbret == 0 )
		dbret = cursor->c_del(cursor, 0);

	if( dbret == 0 ) {
		r = RET_OK;
	} else if( dbret == DB_NOTFOUND ) {
		r = RET_NOTHING;
	} else {
		table_printerror(table, dbret, "c_get");
		(void)cursor->c_close(cursor);
		return RET_DBERR(dbret);
	}
	dbret = cursor->c_close(cursor);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_close");
		return RET_DBERR(dbret);
	}
	return r;
}

bool table_recordexists(struct table *table, const char *key) {
	retvalue r;

	r = table_gettemprecord(table, key, NULL, NULL);
	return RET_IS_OK(r);
}

retvalue table_addrecord(struct table *table, const char *key, const char *data, size_t datalen, bool ignoredups) {
	int dbret;
	DBT Key, Data;

	assert( table != NULL );
	assert( !table->readonly && table->berkeleydb != NULL );

	SETDBT(Key, key);
	SETDBTl(Data, data, datalen + 1);
	dbret = table->berkeleydb->put(table->berkeleydb, NULL,
			&Key, &Data, DB_NODUPDATA);
	if( dbret != 0 && !(ignoredups && dbret == DB_KEYEXIST) ) {
		table_printerror(table, dbret, "put");
		return RET_DBERR(dbret);
	}
	if( table->verbose ) {
		if( table->subname != NULL )
			printf("db: '%s' added to %s(%s).\n",
					key, table->name, table->subname);
		else
			printf("db: '%s' added to %s.\n",
					key, table->name);
	}
	return RET_OK;
}

retvalue table_adduniqsizedrecord(struct table *table, const char *key, const char *data, size_t data_size, bool allowoverwrite, bool nooverwrite) {
	int dbret;
	DBT Key, Data;

	assert( table != NULL );
	assert( !table->readonly && table->berkeleydb != NULL );
	assert( data_size > 0 && data[data_size-1] == '\0' );

	SETDBT(Key, key);
	SETDBTl(Data, data, data_size);
	dbret = table->berkeleydb->put(table->berkeleydb, NULL,
			&Key, &Data, allowoverwrite?0:DB_NOOVERWRITE);
	if( nooverwrite && dbret == DB_KEYEXIST ) {
		/* if nooverwrite is set, do nothing and ignore: */
		return RET_NOTHING;
	}
	if( dbret != 0 ) {
		table_printerror(table, dbret, "put(uniq)");
		return RET_DBERR(dbret);
	}
	if( table->verbose ) {
		if( table->subname != NULL )
			printf("db: '%s' added to %s(%s).\n",
					key, table->name, table->subname);
		else
			printf("db: '%s' added to %s.\n",
					key, table->name);
	}
	return RET_OK;
}
retvalue table_adduniqrecord(struct table *table, const char *key, const char *data) {
	return table_adduniqsizedrecord(table, key, data, strlen(data)+1,
			false, false);
}

retvalue table_deleterecord(struct table *table, const char *key, bool ignoremissing) {
	int dbret;
	DBT Key;

	assert( table != NULL );
	assert( !table->readonly && table->berkeleydb != NULL );

	SETDBT(Key, key);
	dbret = table->berkeleydb->del(table->berkeleydb, NULL, &Key, 0);
	if( dbret != 0 ) {
		if( dbret == DB_NOTFOUND && ignoremissing )
			return RET_NOTHING;
		table_printerror(table, dbret, "del");
		if( dbret == DB_NOTFOUND )
			return RET_ERROR_MISSING;
		else
			return RET_DBERR(dbret);
	}
	if( table->verbose ) {
		if( table->subname != NULL )
			printf("db: '%s' removed from %s(%s).\n",
					key, table->name, table->subname);
		else
			printf("db: '%s' removed from %s.\n",
					key, table->name);
	}
	return RET_OK;
}

retvalue table_replacerecord(struct table *table, const char *key, const char *data) {
	retvalue r;

	r = table_deleterecord(table, key, false);
	if( r != RET_ERROR_MISSING && RET_WAS_ERROR(r) )
		return r;
	return table_adduniqrecord(table, key, data);
}

struct cursor {
	DBC *cursor;
	uint32_t flags;
	retvalue r;
};

retvalue table_newglobalcursor(struct table *table, struct cursor **cursor_p) {
	struct cursor *cursor;
	int dbret;

	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		*cursor_p = NULL;
		return RET_OK;
	}

	cursor = calloc(1, sizeof(struct cursor));
	if( cursor == NULL )
		return RET_ERROR_OOM;

	cursor->cursor = NULL;
	cursor->flags = DB_NEXT;
	cursor->r = RET_OK;
	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL,
			&cursor->cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		free(cursor);
		return RET_DBERR(dbret);
	}
	*cursor_p = cursor;
	return RET_OK;
}

static inline retvalue parse_pair(struct table *table, DBT Key, DBT Data, /*@null@*//*@out@*/const char **key_p, /*@out@*/const char **value_p, /*@out@*/const char **data_p, /*@out@*/size_t *datalen_p) {
	/*@dependant@*/ const char *separator;

	if( Key.size == 0 || Data.size == 0 ||
	    ((const char*)Key.data)[Key.size-1] != '\0' ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not null-terminated) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not null-terminated) data!",
					table->name);
		return RET_ERROR;
	}
	separator = memchr(Data.data, '\0', Data.size-1);
	if( separator == NULL ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted data!",
					table->name);
		return RET_ERROR;
	}
	if( key_p != NULL )
		*key_p = Key.data;
	*value_p = Data.data;
	*data_p = separator + 1;
	*datalen_p = Data.size - (separator - (const char*)Data.data) - 2;
	return RET_OK;
}

retvalue table_newduplicatecursor(struct table *table, const char *key, struct cursor **cursor_p, const char **value_p, const char **data_p, size_t *datalen_p) {
	struct cursor *cursor;
	int dbret;
	DBT Key, Data;
	retvalue r;

	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		*cursor_p = NULL;
		return RET_NOTHING;
	}

	cursor = calloc(1, sizeof(struct cursor));
	if( cursor == NULL )
		return RET_ERROR_OOM;

	cursor->cursor = NULL;
	cursor->flags = DB_NEXT_DUP;
	cursor->r = RET_OK;
	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL,
			&cursor->cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		free(cursor);
		return RET_DBERR(dbret);
	}
	SETDBT(Key, key);
	CLEARDBT(Data);
	dbret = cursor->cursor->c_get(cursor->cursor, &Key, &Data, DB_SET);
	if( dbret == DB_NOTFOUND || dbret == DB_KEYEMPTY ) {
		(void)cursor->cursor->c_close(cursor->cursor);
		free(cursor);
		return RET_NOTHING;
	}
	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_get(DB_SET)");
		(void)cursor->cursor->c_close(cursor->cursor);
		free(cursor);
		return RET_DBERR(dbret);
	}
	r = parse_pair(table, Key, Data, NULL, value_p, data_p, datalen_p);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) ) {
		(void)cursor->cursor->c_close(cursor->cursor);
		free(cursor);
		return r;
	}

	*cursor_p = cursor;
	return RET_OK;
}

retvalue table_newpairedcursor(struct table *table, const char *key, const char *value, struct cursor **cursor_p, const char **data_p, size_t *datalen_p) {
	struct cursor *cursor;
	int dbret;
	DBT Key, Data;
	retvalue r;
	size_t valuelen = strlen(value);

	if( table->berkeleydb == NULL ) {
		assert( table->readonly );
		*cursor_p = NULL;
		return RET_NOTHING;
	}

	cursor = calloc(1, sizeof(struct cursor));
	if( cursor == NULL )
		return RET_ERROR_OOM;

	cursor->cursor = NULL;
	/* cursor_next is not allowed with this type: */
	cursor->flags = DB_GET_BOTH;
	cursor->r = RET_OK;
	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL,
			&cursor->cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		free(cursor);
		return RET_DBERR(dbret);
	}
	SETDBT(Key, key);
	SETDBTl(Data, value, valuelen + 1);
	dbret = cursor->cursor->c_get(cursor->cursor, &Key, &Data, DB_GET_BOTH);
	if( dbret != 0 ) {
		if( dbret == DB_NOTFOUND || dbret == DB_KEYEMPTY ) {
			table_printerror(table, dbret, "c_get(DB_GET_BOTH)");
			r = RET_DBERR(dbret);
		} else
			r = RET_NOTHING;
		(void)cursor->cursor->c_close(cursor->cursor);
		free(cursor);
		return r;
	}
	if( Data.size < valuelen + 2  ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not paired) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not paired) data!",
					table->name);
		(void)cursor->cursor->c_close(cursor->cursor);
		free(cursor);
		return RET_ERROR;
	}
	if( data_p != NULL )
		*data_p = ((const char*)Data.data) + valuelen + 1;
	if( datalen_p != NULL )
		*datalen_p = Data.size - valuelen - 2;
	*cursor_p = cursor;
	return RET_OK;
}

retvalue cursor_close(struct table *table, struct cursor *cursor) {
	int dbret;
	retvalue r;

	if( cursor == NULL )
		return RET_OK;

	r = cursor->r;
	dbret = cursor->cursor->c_close(cursor->cursor);
	cursor->cursor = NULL;
	free(cursor);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_close");
		RET_UPDATE(r, RET_DBERR(dbret));
	}
	return r;
}

bool cursor_nexttemp(struct table *table, struct cursor *cursor, const char **key, const char **data) {
	DBT Key, Data;
	int dbret;

	if( cursor == NULL )
		return false;

	CLEARDBT(Key);
	CLEARDBT(Data);

	dbret = cursor->cursor->c_get(cursor->cursor, &Key, &Data, DB_NEXT);
	if( dbret == DB_NOTFOUND )
		return false;

	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_get(DB_NEXT)");
		cursor->r = RET_DBERR(dbret);
		return false;
	}
	if( Key.size <= 0 || Data.size <= 0 ||
	    ((const char*)Key.data)[Key.size-1] != '\0' ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not null-terminated) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not null-terminated) data!",
					table->name);
		cursor->r = RET_ERROR;
		return false;
	}
	*key = Key.data;
	*data = Data.data;
	return true;
}

bool cursor_nexttempdata(struct table *table, struct cursor *cursor, const char **key, const char **data, size_t *len_p) {
	DBT Key, Data;
	int dbret;

	if( cursor == NULL )
		return false;

	CLEARDBT(Key);
	CLEARDBT(Data);

	dbret = cursor->cursor->c_get(cursor->cursor, &Key, &Data, DB_NEXT);
	if( dbret == DB_NOTFOUND )
		return false;

	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_get(DB_NEXT)");
		cursor->r = RET_DBERR(dbret);
		return false;
	}
	if( Key.size <= 0 || Data.size <= 0 ||
	    ((const char*)Key.data)[Key.size-1] != '\0' ||
	    ((const char*)Data.data)[Data.size-1] != '\0' ) {
		if( table->subname != NULL )
			fprintf(stderr,
"Database %s(%s) returned corrupted (not null-terminated) data!",
					table->name, table->subname);
		else
			fprintf(stderr,
"Database %s returned corrupted (not null-terminated) data!",
					table->name);
		cursor->r = RET_ERROR;
		return false;
	}
	if( key != NULL )
		*key = Key.data;
	*data = Data.data;
	*len_p = Data.size - 1;
	return true;
}

bool cursor_nextpair(struct table *table, struct cursor *cursor, /*@null@*/const char **key_p, const char **value_p, const char **data_p, size_t *datalen_p) {
	DBT Key, Data;
	int dbret;
	retvalue r;

	if( cursor == NULL )
		return false;

	CLEARDBT(Key);
	CLEARDBT(Data);

	dbret = cursor->cursor->c_get(cursor->cursor, &Key, &Data,
			cursor->flags);
	if( dbret == DB_NOTFOUND )
		return false;

	if( dbret != 0 ) {
		table_printerror(table, dbret,
				(cursor->flags==DB_NEXT)?"c_get(DB_NEXT)":
				(cursor->flags==DB_NEXT_DUP)?"c_get(DB_NEXT_DUP)":
				"c_get(DB_???NEXT)");
		cursor->r = RET_DBERR(dbret);
		return false;
	}
	r = parse_pair(table, Key, Data, key_p, value_p, data_p, datalen_p);
	if( RET_WAS_ERROR(r) ) {
		cursor->r = r;
		return false;
	}
	return true;
}

retvalue cursor_replace(struct table *table, struct cursor *cursor, const char *data, size_t datalen) {
	DBT Key, Data;
	int dbret;

	assert( cursor != NULL );
	assert( !table->readonly );

	CLEARDBT(Key);
	SETDBTl(Data, data, datalen + 1);

	dbret = cursor->cursor->c_put(cursor->cursor, &Key, &Data, DB_CURRENT);

	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_put(DB_CURRENT)");
		return RET_DBERR(dbret);
	}
	return RET_OK;
}

retvalue cursor_delete(struct table *table, struct cursor *cursor, const char *key, const char *value) {
	int dbret;

	assert( cursor != NULL );
	assert( !table->readonly );

	dbret = cursor->cursor->c_del(cursor->cursor, 0);

	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_del");
		return RET_DBERR(dbret);
	}
	if( table->verbose ) {
		if( value != NULL )
			if( table->subname != NULL )
				printf("db: '%s' '%s' removed from %s(%s).\n",
						key, value,
						table->name, table->subname);
			else
				printf("db: '%s' '%s' removed from %s.\n",
						key, value, table->name);
		else
			if( table->subname != NULL )
				printf("db: '%s' removed from %s(%s).\n",
						key, table->name, table->subname);
			else
				printf("db: '%s' removed from %s.\n",
						key, table->name);
	}
	return RET_OK;
}

bool table_isempty(struct table *table) {
	DBC *cursor;
	DBT Key, Data;
	int dbret;

	dbret = table->berkeleydb->cursor(table->berkeleydb, NULL,
			&cursor, 0);
	if( dbret != 0 ) {
		table_printerror(table, dbret, "cursor");
		return true;
	}
	CLEARDBT(Key);
	CLEARDBT(Data);

	dbret = cursor->c_get(cursor, &Key, &Data, DB_NEXT);
	if( dbret == DB_NOTFOUND ) {
		(void)cursor->c_close(cursor);
		return true;
	}
	if( dbret != 0 ) {
		table_printerror(table, dbret, "c_get(DB_NEXT)");
		(void)cursor->c_close(cursor);
		return true;
	}
	dbret = cursor->c_close(cursor);
	if( dbret != 0 )
		table_printerror(table, dbret, "c_close");
	return false;
}

/********************************************************************************
 * Open the different types of tables with their needed flags:                  *
 ********************************************************************************/
static retvalue database_table(struct database *database, const char *filename, const char *subtable, enum database_type type, uint32_t flags, /*@out@*/struct table **table_p) {
	struct table *table;
	retvalue r;

	table = calloc(1, sizeof(struct table));
	if( table == NULL )
		return RET_ERROR_OOM;
	/* TODO: is filename always an static constant? then we could drop the dup */
	table->name = strdup(filename);
	if( table->name == NULL ) {
		free(table);
		return RET_ERROR_OOM;
	}
	if( subtable != NULL ) {
		table->subname = strdup(subtable);
		if( table->subname == NULL ) {
			free(table->name);
			free(table);
			return RET_ERROR_OOM;
		}
	} else
		table->subname = NULL;
	table->readonly = ISSET(flags, DB_RDONLY);
	table->verbose = database->verbose;
	r = database_opentable(database, filename, subtable, type, flags, &table->berkeleydb);
	if( RET_WAS_ERROR(r) ) {
		free(table->subname);
		free(table->name);
		free(table);
		return r;
	}
	if( r == RET_NOTHING ) {
		if( ISSET(flags, DB_RDONLY) ) {
			/* sometimes we don't want a return here, when? */
			table->berkeleydb = NULL;
			r = RET_OK;
		} else {
			free(table->subname);
			free(table->name);
			free(table);
			return r;
		}

	}
	*table_p = table;
	return r;
}

retvalue database_openreferences(struct database *db) {
	retvalue r;

	assert( db->references == NULL );
	r = database_table(db, "references.db", "references",
			dbt_BTREEDUP, DB_CREATE, &db->references);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) ) {
		db->references = NULL;
		return r;
	} else
		db->references->verbose = false;
	return RET_OK;
}

/* only compare the first 0-terminated part of the data */
static int paireddatacompare(UNUSED(DB *db), const DBT *a, const DBT *b) {
	if( a->size < b->size )
		return strncmp(a->data, b->data, a->size);
	else
		return strncmp(a->data, b->data, b->size);
}

retvalue database_opentracking(struct database *database, const char *codename, bool readonly, struct table **table_p) {
	struct table *table IFSTUPIDCC(=NULL);
	retvalue r;

	if( database->nopackages ) {
		(void)fputs("Internal Error: Accessing packages databse while that was not prepared!\n", stderr);
		return RET_ERROR;
	}
	if( database->trackingdatabaseopen ) {
		(void)fputs("Internal Error: Trying to open multiple tracking databases at the same time.\nThis should normaly not happen (to avoid triggering bugs in the underlying BerkeleyDB)\n", stderr);
		return RET_ERROR;
	}

	r = database_table(database, "tracking.db", codename,
			dbt_BTREEPAIRS, readonly?DB_RDONLY:DB_CREATE, &table);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) )
		return r;
	table->flagreset = &database->trackingdatabaseopen;
	database->trackingdatabaseopen = true;
	*table_p = table;
	return RET_OK;
}

retvalue database_openpackages(struct database *database, const char *identifier, bool readonly, struct table **table_p) {
	struct table *table IFSTUPIDCC(=NULL);
	retvalue r;

	if( database->nopackages ) {
		(void)fputs("Internal Error: Accessing packages databse while that was not prepared!\n", stderr);
		return RET_ERROR;
	}
	if( database->packagesdatabaseopen ) {
		(void)fputs("Internal Error: Trying to open multiple packages databases at the same time.\nThis should normaly not happen (to avoid triggering bugs in the underlying BerkeleyDB)\n", stderr);
		return RET_ERROR;
	}

	r = database_table(database, "packages.db", identifier,
			dbt_BTREE, readonly?DB_RDONLY:DB_CREATE, &table);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) )
		return r;
	table->flagreset = &database->packagesdatabaseopen;
	database->packagesdatabaseopen = true;
	*table_p = table;
	return RET_OK;
}

/* Get a list of all identifiers having a package list */
retvalue database_listpackages(struct database *database, struct strlist *identifiers) {
	return database_listsubtables(database, "packages.db", identifiers);
}

/* drop a database */
retvalue database_droppackages(struct database *database, const char *identifier) {
	return database_dropsubtable(database, "packages.db", identifier);
}

retvalue database_openfiles(struct database *db) {
	retvalue r;
	struct strlist identifiers;
	bool checksumsexisted, oldfiles;

	assert( db->checksums == NULL );
	assert( db->contents == NULL );

	r = database_listsubtables(db, "contents.cache.db", &identifiers);
	if( RET_IS_OK(r) ) {
		if( strlist_in(&identifiers, "filelists") ) {
			fprintf(stderr,
"Your %s/contents.cache.db file still contains a table of cached file lists\n"
"in the old (pre 3.0.0) format. You have to either delete that file (and lose\n"
"all caches of file lists) or run reprepro with argument translatefilelists\n"
"to translate the old caches into the new format.\n",	global.dbdir);
			strlist_done(&identifiers);
			return RET_ERROR;
		}
		strlist_done(&identifiers);
	}

	r = database_hasdatabasefile(db, "checksums.db", &checksumsexisted);
	r = database_table(db, "checksums.db", "pool",
			dbt_BTREE, DB_CREATE,
			&db->checksums);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) ) {
		db->checksums = NULL;
		return r;
	}
	r = database_hasdatabasefile(db, "files.db", &oldfiles);
	if( RET_WAS_ERROR(r) ) {
		(void)table_close(db->checksums);
		db->checksums = NULL;
		return r;
	}
	if( oldfiles ) {
		fprintf(stderr,
"Error: database uses deprecated format.\n"
"Please run translatelegacychecksums to update to the new format first.\n");
		return RET_ERROR;
	}

	// TODO: only create this file once it is actually needed...
	r = database_table(db, "contents.cache.db", "compressedfilelists",
			dbt_BTREE, DB_CREATE, &db->contents);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) ) {
		(void)table_close(db->checksums);
		db->checksums = NULL;
		db->contents = NULL;
	}
	return r;
}

retvalue database_openreleasecache(struct database *database, const char *codename, struct table **cachedb_p) {
	retvalue r;
	char *oldcachefilename;

	/* Since 3.1.0 it's release.caches.db, before release.cache.db.
	 * The new file also contains the sha1 checksums and is extensible
	 * for more in the future. Thus if there is only the old variant,
	 * rename to the new. (So no old version by accident uses it and
	 * puts the additional sha1 data into the md5sum fields.)
	 * If both files are there, just delete both, as neither will
	 * be very current then.
	 * */

	oldcachefilename = dbfilename("release.cache.db");
	if( oldcachefilename == NULL )
		return RET_ERROR_OOM;
	if( isregularfile(oldcachefilename) ) {
		char *newcachefilename;

		newcachefilename = dbfilename("release.caches.db");
		if( newcachefilename == NULL ) {
			free(oldcachefilename);
			return RET_ERROR_OOM;
		}
		if( isregularfile(newcachefilename)
		    || rename(oldcachefilename, newcachefilename) != 0) {
			fprintf(stderr,
"Deleting old-style export cache file %s!\n"
"This means that all index files (even unchanged) will be rewritten the\n"
"next time parts of their distribution are changed. This should only\n"
"happen once while migration from pre-3.1.0 to later versions.\n",
					oldcachefilename);

			if( unlink(oldcachefilename) != 0 ) {
				int e = errno;
				fprintf(stderr, "Cannot delete '%s': %s!",
						oldcachefilename,
						strerror(e));
				free(oldcachefilename);
				free(newcachefilename);
				return RET_ERRNO(e);
			}
			(void)unlink(oldcachefilename);
		}
		free(newcachefilename);
	}
	free(oldcachefilename);

	r = database_table(database, "release.caches.db", codename,
			 dbt_HASH, DB_CREATE, cachedb_p);
	if( RET_IS_OK(r) )
		(*cachedb_p)->verbose = false;
	return r;
}

static retvalue table_copy(struct table *oldtable, struct table *newtable) {
	retvalue r;
	struct cursor *cursor;
	const char *filekey, *data;
	size_t data_len;

	r = table_newglobalcursor(oldtable, &cursor);
	if( !RET_IS_OK(r) )
		return r;
	while( cursor_nexttempdata(oldtable, cursor, &filekey,
				&data, &data_len) ) {
		r = table_adduniqsizedrecord(newtable, filekey,
				data, data_len+1, false, true);
		if( RET_WAS_ERROR(r) )
			return r;
	}
	return RET_OK;
}

retvalue database_translate_filelists(struct database *database) {
	char *dbname, *tmpdbname;
	struct table *oldtable, *newtable;
	struct strlist identifiers;
	int ret;
	retvalue r, r2;

	r = database_listsubtables(database, "contents.cache.db",
			&identifiers);
	if( RET_IS_OK(r) ) {
		if( !strlist_in(&identifiers, "filelists") ) {
			fprintf(stderr,
"Your %s/contents.cache.db file does not contain an old style database!\n",
					global.dbdir);
			strlist_done(&identifiers);
			return RET_NOTHING;
		}
		strlist_done(&identifiers);
	}

	dbname = dbfilename("contents.cache.db");
	if( dbname == NULL )
		return RET_ERROR_OOM;
	tmpdbname = dbfilename("old.contents.cache.db");
	if( tmpdbname == NULL ) {
		free(dbname);
		return RET_ERROR_OOM;
	}
	ret = rename(dbname, tmpdbname);
	if( ret != 0 ) {
		int e = errno;
		fprintf(stderr, "Could not rename '%s' into '%s': %s(%d)\n",
				dbname, tmpdbname, strerror(e), e);
		free(dbname);
		free(tmpdbname);
		return RET_ERRNO(e);
	}
	newtable = NULL;
	r = database_table(database, "contents.cache.db",
			"compressedfilelists",
			dbt_BTREE, DB_CREATE, &newtable);
	assert( r != RET_NOTHING );
	oldtable = NULL;
	if( RET_IS_OK(r) ) {
		r = database_table(database, "old.contents.cache.db", "filelists",
				dbt_BTREE, DB_RDONLY, &oldtable);
		if( r == RET_NOTHING ) {
			fprintf(stderr, "Could not find old-style database!\n");
			r = RET_ERROR;
		}
	}
	if( RET_IS_OK(r) ) {
		r = filelists_translate(oldtable, newtable);
		if( r == RET_NOTHING )
			r = RET_OK;
	}
	r2 = table_close(oldtable);
	RET_ENDUPDATE(r, r2);
	oldtable = NULL;
	if( RET_IS_OK(r) ) {
		/* copy the new-style database, */
		r = database_table(database, "old.contents.cache.db", "compressedfilelists",
				dbt_BTREE, DB_RDONLY, &oldtable);
		if( RET_IS_OK(r) ) {
			/* if there is one... */
			r = table_copy(oldtable, newtable);
			r2 = table_close(oldtable);
			RET_ENDUPDATE(r, r2);
		}
		if( r == RET_NOTHING ) {
			r = RET_OK;
		}
	}
	r2 = table_close(newtable);
	RET_ENDUPDATE(r, r2);
	if( RET_IS_OK(r) )
		(void)unlink(tmpdbname);

	if( RET_WAS_ERROR(r) ) {
		ret = rename(tmpdbname, dbname);
		if( ret != 0 ) {
			int e = errno;
			fprintf(stderr, "Could not rename '%s' back into '%s': %s(%d)\n",
					dbname, tmpdbname, strerror(e), e);
			free(tmpdbname);
			free(dbname);
			return RET_ERRNO(e);
		}
		free(tmpdbname);
		free(dbname);
		return r;
	}
	free(tmpdbname);
	free(dbname);
	return RET_OK;
}

/* This is already implemented as standalone functions duplicating a bit
 * of database_create and from files.c,
 * because database_create is planed to error out if * there is still an old
 * files.db and files.c is supposed to lose all support for it in the next
 * major version */

static inline retvalue translate(struct table *oldmd5sums, struct table *newchecksums) {
	long numold = 0, numnew = 0, numreplace = 0, numretro = 0;
	struct cursor *cursor, *newcursor;
	const char *filekey, *md5sum, *all;
	size_t alllen;
	retvalue r;

	/* first add all md5sums to checksums if not there yet */

	r = table_newglobalcursor(oldmd5sums, &cursor);
	if( RET_WAS_ERROR(r) )
		return r;
	while( cursor_nexttemp(oldmd5sums, cursor,
				&filekey, &md5sum) ) {
		struct checksums *n = NULL;
		const char *combined;
		size_t combinedlen;

		r = table_gettemprecord(newchecksums, filekey,
				&all, &alllen);
		if( RET_IS_OK(r) )
			r = checksums_setall(&n, all, alllen);
		if( RET_IS_OK(r) ) {
			if( checksums_matches(n, cs_md5sum, md5sum) ) {
				/* already there, nothing to do */
				checksums_free(n);
				numnew++;
				continue;
			}
			/* new item does not match */
			if( verbose > 0 )
				printf(
"Overwriting stale new-checksums entry '%s'!\n",
						filekey);
			numreplace++;
			checksums_free(n);
			n = NULL;
		}
		if( RET_WAS_ERROR(r) ) {
			(void)cursor_close(oldmd5sums, cursor);
			return r;
		}
		/* parse and recreate, to only have sanitized strings
		 * in the database */
		r = checksums_parse(&n, md5sum);
		assert( r != RET_NOTHING );
		if( RET_WAS_ERROR(r) ) {
			(void)cursor_close(oldmd5sums, cursor);
			return r;
		}

		r = checksums_getcombined(n, &combined, &combinedlen);
		assert( r != RET_NOTHING );
		if( !RET_IS_OK(r) ) {
			(void)cursor_close(oldmd5sums, cursor);
			return r;
		}
		numold++;
		r = table_adduniqsizedrecord(newchecksums, filekey,
				combined, combinedlen + 1, true, false);
		assert( r != RET_NOTHING);
		if( !RET_IS_OK(r) ) {
			(void)cursor_close(oldmd5sums, cursor);
			return r;
		}
	}
	r = cursor_close(oldmd5sums, cursor);
	if( RET_WAS_ERROR(r) )
		return r;

	/* then delete everything from checksums that is not in md5sums */

	r = table_newglobalcursor(oldmd5sums, &cursor);
	if( RET_WAS_ERROR(r) )
		return r;
	r = table_newglobalcursor(newchecksums, &newcursor);
	if( RET_WAS_ERROR(r) ) {
		cursor_close(oldmd5sums, cursor);
		return r;
	}
	while( cursor_nexttemp(oldmd5sums, cursor,
				&filekey, &md5sum) ) {
		bool more;
		int cmp;
		const char *newfilekey, *dummy;

		do {
			more = cursor_nexttemp(newchecksums, newcursor,
				&newfilekey, &dummy);
			/* should have been added in the last step */
			assert( more );
			cmp = strcmp(filekey, newfilekey);
			/* should have been added in the last step */
			assert( cmp >= 0 );
			more = cmp > 0;
			if( more ) {
				numretro++;
				if( verbose > 0 )
					printf(
"Deleting stale new-checksums entry '%s'!\n",
						newfilekey);
				r = cursor_delete(newchecksums, newcursor,
						newfilekey, dummy);
				if( RET_WAS_ERROR(r) ) {
					cursor_close(oldmd5sums, cursor);
					cursor_close(newchecksums, newcursor);
					return r;
				}
			}
		} while( more );
	}
	r = cursor_close(oldmd5sums, cursor);
	if( RET_WAS_ERROR(r) )
		return r;
	r = cursor_close(newchecksums, newcursor);
	if( RET_WAS_ERROR(r) )
		return r;
	if( verbose >= 0 ) {
		printf("%ld packages were already in the new checksums.db\n",
				numnew);
		printf("%ld packages were added to the new checksums.db\n",
				numold - numreplace);
		if( numretro != 0 )
			printf(
"%ld were only in checksums.db and not in files.db\n"
"This should only have happened if you added them with a newer version\n"
"and then deleted them with an older version of reprepro.\n",
				numretro);
		if( numreplace != 0 )
			printf(
"%ld were different checksums.db and not in files.db\n"
"This should only have happened if you added them with a newer version\n"
"and then deleted them with an older version of reprepro and\n"
"then readded them with a old version.\n",
				numreplace);
		if( numretro != 0 || numreplace != 0 )
			printf(
"If you never run a old version after a new version,\n"
"you might want to check with check and checkpool if something went wrong.\n");
	}
	return RET_OK;
}

retvalue database_translate_legacy_checksums(bool verbosedb) {
	struct database *n;
	struct table *newchecksums, *oldmd5sums;
	char *fullfilename;
	retvalue r;
	int e;

	if( !isdir(global.dbdir) ) {
		fprintf(stderr, "Cannot find directory '%s'!\n",
				global.dbdir);
		return RET_ERROR;
	}

	n = calloc(1, sizeof(struct database));
	if( n == NULL )
		return RET_ERROR_OOM;

	r = database_lock(n, 0);
	assert( r != RET_NOTHING );
	if( !RET_IS_OK(r) ) {
		database_free(n);
		return r;
	}
	n->readonly = READWRITE;
	n->verbose = verbosedb;

	r = readversionfile(n, false);
	if( RET_WAS_ERROR(r) ) {
		releaselock(n);
		database_free(n);
		return r;
	}

	r = database_table(n, "files.db", "md5sums",
			dbt_BTREE, 0, &oldmd5sums);
	if( r == RET_NOTHING ) {
		fprintf(stderr,
"There is no old files.db in %s. Nothing to translate!\n",
				global.dbdir);
		releaselock(n);
		database_free(n);
		return RET_NOTHING;
	} else if( RET_WAS_ERROR(r) ) {
		releaselock(n);
		database_free(n);
		return r;
	}

	r = database_table(n, "checksums.db", "pool",
			dbt_BTREE, DB_CREATE,
			&newchecksums);
	assert( r != RET_NOTHING );
	if( RET_WAS_ERROR(r) ) {
		(void)table_close(oldmd5sums);
		releaselock(n);
		database_free(n);
		return r;
	}

	r = translate(oldmd5sums, newchecksums);
	if( RET_WAS_ERROR(r) ) {
		(void)table_close(oldmd5sums);
		(void)table_close(newchecksums);
		releaselock(n);
		database_free(n);
		return r;
	}

	(void)table_close(oldmd5sums);
	r = table_close(newchecksums);
	if( RET_WAS_ERROR(r) ) {
		releaselock(n);
		database_free(n);
		return r;
	}
	fullfilename = dbfilename("files.db");
	if( fullfilename == NULL ) {
		releaselock(n);
		database_free(n);
		return RET_ERROR_OOM;
	}
	e = deletefile(fullfilename);
	if( e != 0 ) {
		fprintf(stderr, "Could not delete '%s'!\n"
"It can now savely be deleted and it all that is left to be done!\n",
				fullfilename);
		database_free(n);
		return RET_ERRNO(e);
	}
	r = writeversionfile(n);
	releaselock(n);
	database_free(n);
	return r;
}
