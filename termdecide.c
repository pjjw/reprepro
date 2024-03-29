/*  This file is part of "reprepro"
 *  Copyright (C) 2004,2005,2007,2009 Bernhard R. Link
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

#include <errno.h>
#include <assert.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include "error.h"
#include "mprintf.h"
#include "strlist.h"
#include "names.h"
#include "chunks.h"
#include "globmatch.h"
#include "dpkgversions.h"
#include "terms.h"
#include "termdecide.h"

static inline bool check_field(enum term_comparison c, const char *value, const char *with) {
	if( c == tc_none) {
		return true;
	} else if( c == tc_globmatch ) {
		return globmatch(value, with);
	} else if(c == tc_notglobmatch ) {
		return !globmatch(value, with);
	} else {
		int i;
		i = strcmp(value, with);
		if( i < 0 )
			return c == tc_strictless
				|| c == tc_lessorequal
				|| c == tc_notequal;
		else if( i > 0 )
			return  c == tc_strictmore
				|| c == tc_moreorequal
				|| c == tc_notequal;
		else
			return c == tc_lessorequal
				|| c == tc_moreorequal
				|| c == tc_equal;
	}
}

retvalue term_decidechunk(const term *condition, const char *controlchunk, const void *privdata) {
	const struct term_atom *atom = condition;

	while( atom != NULL ) {
		bool correct;char *value;
		enum term_comparison c = atom->comparison;
		retvalue r;

		if( atom->isspecial ) {
			correct = atom->special.type->compare(c,
					&atom->special.comparewith,
					controlchunk, privdata);
		} else {
			r = chunk_getvalue(controlchunk,
					atom->generic.key, &value);
			if( RET_WAS_ERROR(r) )
				return r;
			if( r == RET_NOTHING ) {
				correct = ( c == tc_notequal
						|| c == tc_notglobmatch);
			} else {
				correct = check_field(c, value,
						atom->generic.comparewith);
				free(value);
			}
		}
		if( atom->negated )
			correct = !correct;
		if( correct ) {
			atom = atom->nextiftrue;
		} else {
			atom = atom->nextiffalse;
			if( atom == NULL) {
				/* do not include */
				return RET_NOTHING;
			}
		}

	}
	/* do include */
	return RET_OK;
}

static retvalue parsestring(enum term_comparison c, const char *value, size_t len, struct compare_with *v) {
	if( c == tc_none ) {
		fprintf(stderr,
"Error: Special formula predicates (those starting with '$') are always\n"
"defined, thus specifying them without parameter to compare against\n"
"makes not sense!\n");
		return RET_ERROR;
	}
	v->pointer = strndup(value, len);
	if( FAILEDTOALLOC(v->pointer) )
		return RET_ERROR_OOM;
	return RET_OK;
}
// TODO: check for well-formed versions
#define parseversion parsestring

static bool comparesource(enum term_comparison c, const struct compare_with *v, const void *d1, const void *d2) {
	const char *control = d1;
	const struct target *target = d2;
	char *package, *source, *version;
	retvalue r;
	bool matches;

	// TODO: make more efficient
	r = chunk_getvalue(control, "Package", &package);
	if( !RET_IS_OK(r) )
		return false;
	r = target->getsourceandversion(control, package, &source, &version);
	free(package);
	if( !RET_IS_OK(r) )
		return false;
	free(version);
	matches = check_field(c, source, v->pointer);
	free(source);
	return matches;
}

static inline bool compare_dpkgversions(enum term_comparison c, const char *version, const char *param) {
	if( c != tc_globmatch && c != tc_notglobmatch ) {
		int cmp;
		retvalue r;

		r = dpkgversions_cmp(version, param, &cmp);
		if( RET_IS_OK(r) ) {
			if( cmp < 0 )
				return c == tc_strictless
					|| c == tc_lessorequal
					|| c == tc_notequal;
			else if( cmp > 0 )
				return c == tc_strictmore
					|| c == tc_moreorequal
					|| c == tc_notequal;
			else
				return c == tc_lessorequal
					|| c == tc_moreorequal
					|| c == tc_equal;
		} else
			return false;
	} else
		return check_field(c, version, param);
}

static bool compareversion(enum term_comparison c, const struct compare_with *v, const void *d1, const void *d2) {
	const char *control = d1;
	const struct target *target = d2;
	char *version;
	retvalue r;
	bool matches;

	r = target->getversion(control, &version);
	if( !RET_IS_OK(r) )
		return false;
	matches = compare_dpkgversions(c, version, v->pointer);
	free(version);
	return matches;
}
static bool comparesourceversion(enum term_comparison c, const struct compare_with *v, const void *d1, const void *d2) {
	const char *control = d1;
	const struct target *target = d2;
	char *package, *source, *version;
	retvalue r;
	bool matches;

	// TODO: make more efficient
	r = chunk_getvalue(control, "Package", &package);
	if( !RET_IS_OK(r) )
		return false;
	r = target->getsourceandversion(control, package, &source, &version);
	free(package);
	if( !RET_IS_OK(r) )
		return false;
	free(source);
	matches = compare_dpkgversions(c, version, v->pointer);
	free(version);
	return matches;
}

static void freestring(UNUSED(enum term_comparison c), struct compare_with *d) {
	free(d->pointer);
}
static void freeatom(enum term_comparison c, struct compare_with *d) {
	if( c != tc_equal && c != tc_notequal )
		free(d->pointer);
}

static retvalue parsetype(enum term_comparison c, const char *value, size_t len, struct compare_with *v) {
	if( c == tc_none ) {
		fprintf(stderr,
"Error: $Type is always defined, it does not make sense without parameter\n"
"to compare against!\n");
		return RET_ERROR;
	}
	if( c != tc_equal && c != tc_notequal ) {
		v->pointer = strndup(value, len);
		if( FAILEDTOALLOC(v->pointer) )
			return RET_ERROR_OOM;
		return RET_OK;
	}
	v->number = packagetype_find_l(value, len);
	if( atom_defined(v->number) )
		return RET_OK;
	fprintf(stderr, "Unknown package type '%.*s' in formula!\n",
			(int)len, value);
	return RET_ERROR;
}

static retvalue parsearchitecture(enum term_comparison c, const char *value, size_t len, struct compare_with *v) {
	if( c == tc_none ) {
		fprintf(stderr,
"Error: $Architecture is always defined, it does not make sense without parameter\n"
"to compare against!\n");
		return RET_ERROR;
	}
	if( c != tc_equal && c != tc_notequal ) {
		v->pointer = strndup(value, len);
		if( FAILEDTOALLOC(v->pointer) )
			return RET_ERROR_OOM;
		return RET_OK;
	}
	v->number = architecture_find_l(value, len);
	if( atom_defined(v->number) )
		return RET_OK;
	fprintf(stderr, "Unknown architecture '%.*s' in formula (must be listed in conf/distributions to be known)!\n",
			(int)len, value);
	return RET_ERROR;
}

static retvalue parsecomponent(enum term_comparison c, const char *value, size_t len, struct compare_with *v) {
	if( c == tc_none ) {
		fprintf(stderr,
"Error: $Component is always defined, it does not make sense without parameter\n"
"to compare against!\n");
		return RET_ERROR;
	}
	if( c != tc_equal && c != tc_notequal ) {
		v->pointer = strndup(value, len);
		if( FAILEDTOALLOC(v->pointer) )
			return RET_ERROR_OOM;
		return RET_OK;
	}
	v->number = component_find_l(value, len);
	if( atom_defined(v->number) )
		return RET_OK;
	fprintf(stderr, "Unknown component '%.*s' in formula (must be listed in conf/distributions to be known)!\n", (int)len, value);
	return RET_ERROR;
}

static bool comparetype(enum term_comparison c, const struct compare_with *v, UNUSED(const void *d1), const void *d2) {
	const struct target *target = d2;

	if( c == tc_equal )
		return v->number == target->packagetype_atom;
	else if( c == tc_notequal )
		return v->number != target->packagetype_atom;
	else
		return check_field(c,
				atoms_packagetypes[target->packagetype_atom],
				v->pointer);

}
static bool comparearchitecture(enum term_comparison c, const struct compare_with *v, UNUSED(const void *d1), const void *d2) {
	const struct target *target = d2;

	if( c == tc_equal )
		return v->number == target->architecture_atom;
	else if( c == tc_notequal )
		return v->number != target->architecture_atom;
	else
		return check_field(c,
				atoms_architectures[target->architecture_atom],
				v->pointer);
}
static bool comparecomponent(enum term_comparison c, const struct compare_with *v, UNUSED(const void *d1), const void *d2) {
	const struct target *target = d2;

	if( c == tc_equal )
		return v->number == target->component_atom;
	else if( c == tc_notequal )
		return v->number != target->component_atom;
	else
		return check_field(c,
				atoms_components[target->component_atom],
				v->pointer);
}

static struct term_special targetdecisionspecial[] = {
	{"$Source", parsestring, comparesource, freestring},
	{"$SourceVersion", parseversion, comparesourceversion, freestring},
	{"$Version", parseversion, compareversion, freestring},
	{"$Architecture", parsearchitecture, comparearchitecture, freeatom},
	{"$Component", parsecomponent, comparecomponent, freeatom},
	{"$Type", parsetype, comparetype, freeatom},
	{"$PackageType", parsetype, comparetype, freeatom},
	{NULL, NULL, NULL, NULL}
};

retvalue term_compilefortargetdecision(term **term_p, const char *formula) {
	return term_compile(term_p, formula,
		T_GLOBMATCH|T_OR|T_BRACKETS|T_NEGATION|T_VERSION|T_NOTEQUAL,
		targetdecisionspecial);
}

retvalue term_decidechunktarget(const term *condition, const char *controlchunk, const struct target *target) {
	return term_decidechunk(condition, controlchunk, target);
}
