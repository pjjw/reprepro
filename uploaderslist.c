/*  This file is part of "reprepro"
 *  Copyright (C) 2005,2006,2007,2009,2011 Bernhard R. Link
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
#include <alloca.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include "error.h"
#include "mprintf.h"
#include "strlist.h"
#include "names.h"
#include "atoms.h"
#include "signature.h"
#include "globmatch.h"
#include "uploaderslist.h"

struct upload_condition {
	/* linked list of all sub-nodes */
	/*@null@*/struct upload_condition *next;

	enum upload_condition_type type;
	const struct upload_condition *next_if_true, *next_if_false;
	bool accept_if_true, accept_if_false;
	enum {
		/* none matching means false, at least one being from
		 * the set means true */
		needs_any = 0,
		/* one not matching means false, otherwise true */
		needs_all,
		/* one not matching means false,
		 * otherwise true iff there is at least one */
		needs_existsall,
		/* having a candidate means true, otherwise false */
		needs_anycandidate
	} needs;
	union {
		/* uc_SECTIONS, uc_BINARIES, uc_SOURCENAME, uc_BYHAND,
		 * uc_CODENAME,  */
		struct strlist strings;
		/* uc_COMPONENTS, uc_ARCHITECTURES */
		struct atomlist atoms;
	};
};
struct upload_conditions {
	/* condition currently tested */
	const struct upload_condition *current;
	/* current state of top most condition */
	bool matching;
	/* top most condition will not be true unless cleared*/
	bool needscandidate;
	/* always use last next, then decrement */
	int count;
	const struct upload_condition *conditions[];
};

static retvalue upload_conditions_add(struct upload_conditions **c_p, const struct upload_condition *a) {
	int newcount;
	struct upload_conditions *n;

	if (a->type == uc_REJECTED) {
		/* due to groups, there can be empty conditions.
		 * Don't include those in this list... */
		return RET_OK;
	}

	if (*c_p == NULL)
		newcount = 1;
	else
		newcount = (*c_p)->count + 1;
	n = realloc(*c_p, sizeof(struct upload_conditions)
			+ newcount * sizeof(const struct upload_condition*));
	if (FAILEDTOALLOC(n))
		return RET_ERROR_OOM;
	n->current = NULL;
	n->count = newcount;
	n->conditions[newcount - 1] = a;
	*c_p = n;
	return RET_OK;
}

struct uploadergroup {
	struct uploadergroup *next;
	size_t len;
	char *name;
	/* NULL terminated list of pointers, or NULL for none */
	const struct uploadergroup **memberof;
	struct upload_condition permissions;
	/* line numbers (if != 0) to allow some diagnostics */
	unsigned long firstmemberat, emptyat, firstusedat, unusedat;
};

struct uploader {
	struct uploader *next;
	/* NULL terminated list of pointers, or NULL for none */
	const struct uploadergroup **memberof;
	size_t len;
	char *reversed_fingerprint;
	struct upload_condition permissions;
	bool allow_subkeys;
};

static struct uploaders {
	struct uploaders *next;
	size_t reference_count;
	char *filename;
	size_t filename_len;

	struct uploadergroup *groups;
	struct uploader *by_fingerprint;
	struct upload_condition anyvalidkeypermissions;
	struct upload_condition unsignedpermissions;
	struct upload_condition anybodypermissions;
} *uploaderslists = NULL;

static void uploadpermission_release(struct upload_condition *p) {
	struct upload_condition *h, *f = NULL;

	assert (p != NULL);

	do {
		h = p->next;
		switch (p->type) {
			case uc_BINARIES:
			case uc_SECTIONS:
			case uc_SOURCENAME:
			case uc_BYHAND:
			case uc_CODENAME:
				strlist_done(&p->strings);
				break;

			case uc_ARCHITECTURES:
				atomlist_done(&p->atoms);
				break;

			case uc_ALWAYS:
			case uc_REJECTED:
				break;
		}
		free(f);
		/* next one must be freed: */
		f = h;
		/* and processed: */
		p = h;
	} while (p != NULL);
}

static void uploadergroup_free(struct uploadergroup *u) {
	if (u == NULL)
		return;
	free(u->name);
	free(u->memberof);
	uploadpermission_release(&u->permissions);
	free(u);
}

static void uploader_free(struct uploader *u) {
	if (u == NULL)
		return;
	free(u->reversed_fingerprint);
	free(u->memberof);
	uploadpermission_release(&u->permissions);
	free(u);
}

static void uploaders_free(struct uploaders *u) {
	if (u == NULL)
		return;
	while (u->by_fingerprint != NULL) {
		struct uploader *next = u->by_fingerprint->next;

		uploader_free(u->by_fingerprint);
		u->by_fingerprint = next;
	}
	while (u->groups != NULL) {
		struct uploadergroup *next = u->groups->next;

		uploadergroup_free(u->groups);
		u->groups = next;
	}
	uploadpermission_release(&u->anyvalidkeypermissions);
	uploadpermission_release(&u->anybodypermissions);
	uploadpermission_release(&u->unsignedpermissions);
	free(u->filename);
	free(u);
}

void uploaders_unlock(struct uploaders *u) {
	if (u->reference_count > 1) {
		u->reference_count--;
	} else {
		struct uploaders **p = &uploaderslists;

		assert (u->reference_count == 1);
		/* avoid double free: */
		if (u->reference_count == 0)
			return;

		while (*p != NULL && *p != u)
			p = &(*p)->next;
		assert (p != NULL && *p == u);
		if (*p == u) {
			*p = u->next;
			uploaders_free(u);
		}
	}
}

static retvalue upload_conditions_add_group(struct upload_conditions **c_p, const struct uploadergroup **groups) {
	const struct uploadergroup *group;
	retvalue r;

	while ((group = *(groups++)) != NULL) {
		r = upload_conditions_add(c_p, &group->permissions);
		if (!RET_WAS_ERROR(r) && group->memberof != NULL)
			r = upload_conditions_add_group(c_p, group->memberof);
		if (RET_WAS_ERROR(r))
			return r;
	}
	return RET_OK;
}

static retvalue find_key_and_add(struct uploaders *u, struct upload_conditions **c_p, const struct signature *s) {
	size_t len, i, primary_len;
	char *reversed;
	const char *fingerprint, *primary_fingerprint;
	char *reversed_primary_key;
	const struct uploader *uploader;
	retvalue r;

	assert (u != NULL);

	fingerprint = s->keyid;
	assert (fingerprint != NULL);
	len = strlen(fingerprint);
	reversed = alloca(len+1);
	if (FAILEDTOALLOC(reversed))
		return RET_ERROR_OOM;
	for (i = 0 ; i < len ; i++) {
		char c = fingerprint[len-i-1];
		if (c >= 'a' && c <= 'f')
			c -= 'a' - 'A';
		else if (c == 'x' && len-i-1 == 1 && fingerprint[0] == '0')
			break;
		if ((c < '0' || c > '9') && (c <'A' && c > 'F')) {
			fprintf(stderr,
"Strange character '%c'(=%hhu) in fingerprint '%s'.\n"
"Search for appropriate rules in the uploaders file might fail.\n",
					c, c, fingerprint);
			break;
		}
		reversed[i] = c;
	}
	len = i;
	reversed[len] = '\0';

	/* hm, this only sees the key is expired when it is kind of late... */
	primary_fingerprint = s->primary_keyid;
	primary_len = strlen(primary_fingerprint);
	reversed_primary_key = alloca(len+1);
	if (FAILEDTOALLOC(reversed_primary_key))
		return RET_ERROR_OOM;

	for (i = 0 ; i < primary_len ; i++) {
		char c = primary_fingerprint[primary_len-i-1];
		if (c >= 'a' && c <= 'f')
			c -= 'a' - 'A';
		else if (c == 'x' && primary_len-i-1 == 1 &&
				primary_fingerprint[0] == '0')
			break;
		if ((c < '0' || c > '9') && (c <'A' && c > 'F')) {
			fprintf(stderr,
"Strange character '%c'(=%hhu) in fingerprint/key-id '%s'.\n"
"Search for appropriate rules in the uploaders file might fail.\n",
					c, c, primary_fingerprint);
			break;
		}
		reversed_primary_key[i] = c;
	}
	primary_len = i;
	reversed_primary_key[primary_len] = '\0';

	for (uploader = u->by_fingerprint ; uploader != NULL ;
	                                    uploader = uploader->next) {
		/* TODO: allow ignoring */
		if (s->state != sist_valid)
			continue;
		if (uploader->allow_subkeys) {
			if (uploader->len > primary_len)
				continue;
			if (memcmp(uploader->reversed_fingerprint,
						reversed_primary_key,
						uploader->len) != 0)
				continue;
		} else {
			if (uploader->len > len)
				continue;
			if (memcmp(uploader->reversed_fingerprint,
						reversed, uploader->len) != 0)
				continue;
		}
		r = upload_conditions_add(c_p, &uploader->permissions);
		if (!RET_WAS_ERROR(r) && uploader->memberof != NULL)
			r = upload_conditions_add_group(c_p,
					uploader->memberof);
		if (RET_WAS_ERROR(r))
			return r;
		/* no break here, as a key might match
		 * multiple specifications of different length */
	}
	return RET_OK;
}

retvalue uploaders_permissions(struct uploaders *u, const struct signatures *signatures, struct upload_conditions **c_p) {
	struct upload_conditions *conditions = NULL;
	retvalue r;
	int j;

	r = upload_conditions_add(&conditions,
			&u->anybodypermissions);
	if (RET_WAS_ERROR(r))
		return r;
	if (signatures == NULL) {
		/* signatures.count might be 0 meaning there is
		 * something lile a gpg header but we could not get
		 * keys, because of a gpg error or because of being
		 * compiling without libgpgme */
		r = upload_conditions_add(&conditions,
				&u->unsignedpermissions);
		if (RET_WAS_ERROR(r)) {
			free(conditions);
			return r;
		}
	}
	if (signatures != NULL && signatures->validcount > 0) {
		r = upload_conditions_add(&conditions,
				&u->anyvalidkeypermissions);
		if (RET_WAS_ERROR(r)) {
			free(conditions);
			return r;
		}
	}
	if (signatures != NULL) {
		for (j = 0 ; j < signatures->count ; j++) {
			r = find_key_and_add(u, &conditions,
					&signatures->signatures[j]);
			if (RET_WAS_ERROR(r)) {
				free(conditions);
				return r;
			}
		}
	}
	*c_p = conditions;
	return RET_OK;
}

/* uc_FAILED means rejected, uc_ACCEPTED means can go in */
enum upload_condition_type uploaders_nextcondition(struct upload_conditions *c) {

	if (c->current != NULL) {
		if (c->matching && !c->needscandidate) {
			if (c->current->accept_if_true)
				return uc_ACCEPTED;
			c->current = c->current->next_if_true;
		} else {
			if (c->current->accept_if_false)
				return uc_ACCEPTED;
			c->current = c->current->next_if_false;
		}
	}

	/* return the first non-trivial one left: */
	while (true) {
		while (c->current != NULL) {
			assert (c->current->type > uc_REJECTED);
			if (c->current->type == uc_ALWAYS) {
				if (c->current->accept_if_true)
					return uc_ACCEPTED;
				c->current = c->current->next_if_true;
			} else {
				/* empty set fullfills all conditions,
				   but not an exists condition */
				switch (c->current->needs) {
					case needs_any:
						c->matching = false;
						c->needscandidate = false;
						break;
					case needs_all:
						c->matching = true;
						c->needscandidate = false;
						break;
					case needs_existsall:
					case needs_anycandidate:
						c->matching = true;
						c->needscandidate = true;
						break;
				}
				return c->current->type;
			}
		}
		if (c->count == 0)
			return uc_REJECTED;
		c->count--;
		c->current = c->conditions[c->count];
	}
	/* not reached */
}

static bool match_namecheck(const struct strlist *strings, const char *name) {
	int i;

	for (i = 0 ; i < strings->count ; i++) {
		if (globmatch(name, strings->values[i]))
			return true;
	}
	return false;
}

bool uploaders_verifystring(struct upload_conditions *conditions, const char *name) {
	const struct upload_condition *c = conditions->current;

	assert (c != NULL);
	assert (c->type == uc_BINARIES || c->type == uc_SECTIONS ||
		c->type == uc_CODENAME ||
		c->type == uc_SOURCENAME || c->type == uc_BYHAND);

	conditions->needscandidate = false;
	switch (conditions->current->needs) {
		case needs_all:
		case needs_existsall:
			/* once one condition is false, the case is settled */

			if (conditions->matching &&
					!match_namecheck(&c->strings, name))
				conditions->matching = false;
			/* but while it is true, more info is needed */
			return conditions->matching;
		case needs_any:
			/* once one condition is true, the case is settled */
			if (!conditions->matching &&
					match_namecheck(&c->strings, name))
				conditions->matching = true;
			conditions->needscandidate = false;
			/* but while it is false, more info is needed */
			return !conditions->matching;
		case needs_anycandidate:
			/* we are settled, no more information needed */
			return false;
	}
	/* NOT REACHED */
	assert (conditions->current->needs != conditions->current->needs);
}

bool uploaders_verifyatom(struct upload_conditions *conditions, atom_t atom) {
	const struct upload_condition *c = conditions->current;

	assert (c != NULL);
	assert (c->type == uc_ARCHITECTURES);

	conditions->needscandidate = false;
	switch (conditions->current->needs) {
		case needs_all:
		case needs_existsall:
			/* once one condition is false, the case is settled */

			if (conditions->matching &&
					!atomlist_in(&c->atoms, atom))
				conditions->matching = false;
			/* but while it is true, more info is needed */
			return conditions->matching;
		case needs_any:
			/* once one condition is true, the case is settled */
			if (!conditions->matching &&
					atomlist_in(&c->atoms, atom))
				conditions->matching = true;
			/* but while it is false, more info is needed */
			return !conditions->matching;
		case needs_anycandidate:
			/* we are settled, no more information needed */
			return false;
	}
	/* NOT REACHED */
	assert (conditions->current->needs != conditions->current->needs);
}

static struct uploader *addfingerprint(struct uploaders *u, const char *fingerprint, size_t len, bool allow_subkeys) {
	size_t i;
	char *reversed = malloc(len+1);
	struct uploader *uploader, **last;

	if (FAILEDTOALLOC(reversed))
		return NULL;
	for (i = 0 ; i < len ; i++) {
		char c = fingerprint[len-i-1];
		if (c >= 'a' && c <= 'f')
			c -= 'a' - 'A';
		assert ((c >= '0' && c <= '9') || (c >= 'A' || c <= 'F'));
		reversed[i] = c;
	}
	reversed[len] = '\0';
	last = &u->by_fingerprint;
	for (uploader = u->by_fingerprint ;
	     uploader != NULL ;
	     uploader = *(last = &uploader->next)) {
		if (uploader->len != len)
			continue;
		if (memcmp(uploader->reversed_fingerprint, reversed, len) != 0)
			continue;
		if (uploader->allow_subkeys != allow_subkeys)
			continue;
		free(reversed);
		return uploader;
	}
	assert (*last == NULL);
	uploader = zNEW(struct uploader);
	if (FAILEDTOALLOC(uploader))
		return NULL;
	*last = uploader;
	uploader->reversed_fingerprint = reversed;
	uploader->len = len;
	uploader->allow_subkeys = allow_subkeys;
	return uploader;
}

static struct uploadergroup *addgroup(struct uploaders *u, const char *name, size_t len) {
	struct uploadergroup *group, **last;

	last = &u->groups;
	for (group = u->groups ;
	     group != NULL ; group = *(last = &group->next)) {
		if (group->len != len)
			continue;
		if (memcmp(group->name, name, len) != 0)
			continue;
		return group;
	}
	assert (*last == NULL);
	group = zNEW(struct uploadergroup);
	if (FAILEDTOALLOC(group))
		return NULL;
	group->name = strndup(name, len);
	group->len = len;
	if (FAILEDTOALLOC(group->name)) {
		free(group);
		return NULL;
	}
	*last = group;
	return group;
}

static inline const char *overkey(const char *p) {
	while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f')
			|| (*p >= 'A' && *p <= 'F')) {
		p++;
	}
	return p;
}

static retvalue parse_stringpart(/*@out@*/struct strlist *strings, const char **pp, const char *filename, long lineno, int column) {
	const char *p = *pp;
	retvalue r;

	strlist_init(strings);
	do {
		const char *startp, *endp;
		char *n;

		while (*p != '\0' && xisspace(*p))
			p++;
		if (*p != '\'') {
			fprintf(stderr,
"%s:%lu:%u: starting \"'\" expected!\n",
					filename, lineno,
					column + (int)(p - *pp));
			return RET_ERROR;
		}
		p++;
		startp = p;
		while (*p != '\0' && *p != '\'')
			p++;
		if (*p == '\0') {
			fprintf(stderr,
"%s:%lu:%u: closing \"'\" expected!\n",
					filename, lineno,
					column + (int)(p - *pp));
			return RET_ERROR;
		}
		assert (*p == '\'');
		endp = p;
		p++;
		n = strndup(startp, endp - startp);
		if (FAILEDTOALLOC(n))
			return RET_ERROR_OOM;
		r = strlist_adduniq(strings, n);
		if (RET_WAS_ERROR(r))
			return r;
		while (*p != '\0' && xisspace(*p))
			p++;
		column += (p - *pp);
		*pp = p;
		if (**pp == '|') {
			p++;
		}
	} while (**pp == '|');
	*pp = p;
	return RET_OK;
}

static retvalue parse_architectures(/*@out@*/struct atomlist *atoms, const char **pp, const char *filename, long lineno, int column) {
	const char *p = *pp;
	retvalue r;

	atomlist_init(atoms);
	do {
		const char *startp, *endp;
		atom_t atom;

		while (*p != '\0' && xisspace(*p))
			p++;
		if (*p != '\'') {
			fprintf(stderr,
"%s:%lu:%u: starting \"'\" expected!\n",
					filename, lineno,
					column + (int)(p - *pp));
			return RET_ERROR;
		}
		p++;
		startp = p;
		while (*p != '\0' && *p != '\'' && *p != '*' && *p != '?')
			p++;
		if (*p == '*' || *p == '?') {
			fprintf(stderr,
"%s:%lu:%u: Wildcards are not allowed in architectures!\n",
					filename, lineno,
					column + (int)(p - *pp));
			return RET_ERROR;
		}
		if (*p == '\0') {
			fprintf(stderr,
"%s:%lu:%u: closing \"'\" expected!\n",
					filename, lineno,
					column + (int)(p - *pp));
			return RET_ERROR;
		}
		assert (*p == '\'');
		endp = p;
		p++;
		atom = architecture_find_l(startp, endp - startp);
		if (!atom_defined(atom)) {
			fprintf(stderr,
"%s:%lu:%u: Unknown architecture '%.*s'! (Did you mistype?)\n",
					filename, lineno,
					column + (int)(startp-*pp),
					(int)(endp-startp), startp);
			return RET_ERROR;
		}
		r = atomlist_add_uniq(atoms, atom);
		if (RET_WAS_ERROR(r))
			return r;
		while (*p != '\0' && xisspace(*p))
			p++;
		column += (p - *pp);
		*pp = p;
		if (**pp == '|') {
			p++;
		}
	} while (**pp == '|');
	*pp = p;
	return RET_OK;
}

static retvalue parse_condition(const char *filename, long lineno, int column, const char **pp, /*@out@*/struct upload_condition *condition) {
	const char *p = *pp;
	struct upload_condition *fallback, *last, *or_scope;

	memset(condition, 0, sizeof(struct upload_condition));

	/* allocate a new fallback-node:
	 * (this one is used to make it easier to concatenate those decision
	 * trees, especially it keeps open the possibility to have deny
	 * decisions) */
	fallback = zNEW(struct upload_condition);
	if (FAILEDTOALLOC(fallback))
		return RET_ERROR_OOM;
	fallback->type = uc_ALWAYS;
	assert(!fallback->accept_if_true);

	/* the queue with next has all nodes, so they can be freed
	 * (or otherwise modified) */
	condition->next = fallback;


	last = condition;
	or_scope = condition;

	while (true) {
		if (strncmp(p, "not", 3) == 0 &&
				xisspace(p[3])) {
			p += 3;
			while (*p != '\0' && xisspace(*p))
				p++;
			/* negate means false is good and true
			 * is bad: */
			last->accept_if_false = true;
			last->accept_if_true = false;
			last->next_if_false = NULL;
			last->next_if_true = fallback;
		} else {
			last->accept_if_false = false;
			last->accept_if_true = true;
			last->next_if_false = fallback;
			last->next_if_true = NULL;
		}
		if (p[0] == '*' && xisspace(p[1])) {
			last->type = uc_ALWAYS;
			p++;
		} else if (strncmp(p, "architectures", 13) == 0 &&
			   strchr(" \t'", p[13]) != NULL) {
			retvalue r;

			last->type = uc_ARCHITECTURES;
			last->needs = needs_all;
			p += 13;
			while (*p != '\0' && xisspace(*p))
				p++;
			if (strncmp(p, "contain", 7) == 0 &&
					strchr(" \t'", p[7]) != NULL) {
				last->needs = needs_any;
				p += 7;
			}

			r = parse_architectures(&last->atoms, &p,
					filename, lineno,
					column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}
		} else if (strncmp(p, "binaries", 8) == 0 &&
			   strchr(" \t'", p[8]) != NULL) {
			retvalue r;

			last->type = uc_BINARIES;
			last->needs = needs_all;
			p += 8;
			while (*p != '\0' && xisspace(*p))
				p++;
			if (strncmp(p, "contain", 7) == 0 &&
					strchr(" \t'", p[7]) != NULL) {
				last->needs = needs_any;
				p += 7;
			}

			r = parse_stringpart(&last->strings, &p,
					filename, lineno,
					column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}
		} else if (strncmp(p, "byhand", 6) == 0 &&
			   strchr(" \t'", p[6]) != NULL) {
			retvalue r;

			last->type = uc_BYHAND;
			last->needs = needs_existsall;
			p += 8;
			while (*p != '\0' && xisspace(*p))
				p++;
			if (*p != '\'') {
				strlist_init(&last->strings);
				r = RET_OK;
			} else
				r = parse_stringpart(&last->strings, &p,
						filename, lineno,
						column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}
		} else if (strncmp(p, "sections", 8) == 0 &&
			   strchr(" \t'", p[8]) != NULL) {
			retvalue r;

			last->type = uc_SECTIONS;
			last->needs = needs_all;
			p += 8;
			while (*p != '\0' && xisspace(*p))
				p++;
			if (strncmp(p, "contain", 7) == 0 &&
					strchr(" \t'", p[7]) != NULL) {
				last->needs = needs_any;
				p += 7;
			}

			r = parse_stringpart(&last->strings, &p,
					filename, lineno,
					column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}
		} else if (strncmp(p, "source", 6) == 0 &&
			   strchr(" \t'", p[6]) != NULL) {
			retvalue r;

			last->type = uc_SOURCENAME;
			p += 6;

			r = parse_stringpart(&last->strings, &p,
					filename, lineno,
					column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}

		} else if (strncmp(p, "distribution", 12) == 0 &&
			   strchr(" \t'", p[12]) != NULL) {
			retvalue r;

			last->type = uc_CODENAME;
			p += 12;

			r = parse_stringpart(&last->strings, &p,
					filename, lineno,
					column + (p-*pp));
			if (RET_WAS_ERROR(r)) {
				uploadpermission_release(condition);
				return r;
			}

		} else {
			fprintf(stderr,
"%s:%lu:%u: condition expected after 'allow' keyword!\n",
					filename, lineno,
					column + (int)(p - *pp));
			uploadpermission_release(condition);
			return RET_ERROR;
		}
		while (*p != '\0' && xisspace(*p))
			p++;
		if (strncmp(p, "and", 3) == 0 && xisspace(p[3])) {
			struct upload_condition *n, *c;

			p += 3;

			n = zNEW(struct upload_condition);
			if (FAILEDTOALLOC(n)) {
				uploadpermission_release(condition);
				return RET_ERROR_OOM;
			}
			/* everything that yet made it succeed makes it need
			 * to check this condition: */
			for (c = condition ; c != NULL ; c = c->next) {
				if (c->accept_if_true) {
					c->next_if_true = n;
					c->accept_if_true = false;
				}
				if (c->accept_if_false) {
					c->next_if_false = n;
					c->accept_if_false = false;
				}
			}
			/* or will only bind to this one */
			or_scope = n;

			/* add it to queue: */
			assert (last->next == fallback);
			n->next = fallback;
			last->next = n;
			last = n;
		} else if (strncmp(p, "or", 2) == 0 && xisspace(p[2])) {
			struct upload_condition *n, *c;

			p += 2;

			n = zNEW(struct upload_condition);
			if (FAILEDTOALLOC(n)) {
				uploadpermission_release(condition);
				return RET_ERROR_OOM;
			}
			/* everything in current scope that made it fail
			 * now makes it check this: (currently that will
			 * only be true at most for c == last, but with
			 * parantheses this all will be needed) */
			for (c = or_scope ; c != NULL ; c = c->next) {
				if (c->next_if_true == fallback)
					c->next_if_true = n;
				if (c->next_if_false == fallback)
					c->next_if_false = n;
			}
			/* add it to queue: */
			assert (last->next == fallback);
			n->next = fallback;
			last->next = n;
			last = n;
		} else if (strncmp(p, "by", 2) == 0 && xisspace(p[2])) {
			p += 2;
			break;
		} else {
			fprintf(stderr,
"%s:%lu:%u: 'by','and' or 'or' keyword expected!\n",
					filename, (long)lineno,
					column + (int)(p - *pp));
			uploadpermission_release(condition);
			memset(condition, 0, sizeof(struct upload_condition));
			return RET_ERROR;
		}
		while (*p != '\0' && xisspace(*p))
			p++;
	}
	*pp = p;
	return RET_OK;
}

static void condition_add(struct upload_condition *permissions, struct upload_condition *c) {
	if (permissions->next == NULL) {
		/* first condition, as no fallback yet allocated */
		*permissions = *c;
		memset(c, 0, sizeof(struct upload_condition));
	} else {
		struct upload_condition *last;

		last = permissions->next;
		assert (last != NULL);
		while (last->next != NULL)
			last = last->next;

		/* the very last is always the fallback-node to which all
		 * other conditions fall back if they have no decision */
		assert(last->type = uc_ALWAYS);
		assert(!last->accept_if_true);

		*last = *c;
		memset(c, 0, sizeof(struct upload_condition));
	}
}

static retvalue find_group(struct uploadergroup **g, struct uploaders *u, const char **pp, const char *filename, long lineno, const char *buffer) {
	const char *p, *q;
	struct uploadergroup *group;

	p = *pp;
	q = p;
	while ((*q >= 'a' && *q <= 'z') || (*q >= 'A' && *q <= 'Z') ||
			(*q >= '0' && *q <= '9') || *q == '-'
			|| *q == '_' || *q == '.')
		q++;
	if (*p == '\0' || (q-p == 3 && memcmp(p, "add", 3) == 0)
			|| (q-p == 5 && memcmp(p, "empty", 5) == 0)
			|| (q-p == 6 && memcmp(p, "unused", 6) == 0)
			|| (q-p == 8 && memcmp(p, "contains", 8) == 0)) {
		fprintf(stderr, "%s:%lu:%u: group name expected!\n", filename,
				(long)lineno, (int)(1 + p - buffer));
		return RET_ERROR;
	}
	if (*q != '\0' && *q != ' ' && *q != '\t') {
		fprintf(stderr, "%s:%lu:%u: invalid group name!\n",
				filename, (long)lineno, (int)(1 +p -buffer));
		return RET_ERROR;
	}
	*pp = q;
	group = addgroup(u, p, q-p);
	if (FAILEDTOALLOC(group))
		return RET_ERROR_OOM;
	*g = group;
	return RET_OK;
}

static retvalue find_uploader(struct uploader **u_p, struct uploaders *u, const char *p, const char *filename, long lineno, const char *buffer) {
	struct uploader *uploader;
	bool allow_subkeys = false;
	const char *q, *qq;

	if (p[0] == '0' && p[1] == 'x')
		p += 2;
	q = overkey(p);
	if (*p == '\0' || (*q !='\0' && !xisspace(*q) && *q != '+') || q==p) {
		fprintf(stderr, "%s:%lu:%u: key id or fingerprint expected!\n",
				filename, (long)lineno, (int)(1 + q - buffer));
		return RET_ERROR;
	}
	qq = q;
	while (xisspace(*qq))
		qq++;
	if (*qq == '+') {
		qq++;
		allow_subkeys = true;
	}
	while (xisspace(*qq))
		qq++;
	if (*qq != '\0') {
		fprintf(stderr, 
"%s:%lu:%u: unexpected data after 'key <fingerprint>' statement!\n\n",
				filename, (long)lineno, (int)(1 +qq - buffer));
		if (*q == ' ')
			fprintf(stderr,
" Hint: no spaces allowed in fingerprint specification.\n");
		return RET_ERROR;
	}
	uploader = addfingerprint(u, p, q-p, allow_subkeys);
	if (FAILEDTOALLOC(uploader))
		return RET_ERROR_OOM;
	*u_p = uploader;
	return RET_OK;
}

static retvalue include_group(struct uploadergroup *group, const struct uploadergroup ***memberof_p, const char *filename, long lineno) {
	size_t n;
	const struct uploadergroup **memberof = *memberof_p;

	n = 0;
	if (memberof != NULL) {
		while (memberof[n] != NULL) {
			if (memberof[n] == group) {
				fprintf(stderr,
"%s:%lu: member added to group %s a second time!\n",
						filename, lineno, group->name);
				return RET_ERROR;
			}
			n++;
		}
	}
	if (n == 0 || (n & 15) == 15) {
		/* let's hope no static checker is confused here ;-> */
		memberof = realloc(memberof,
				((n+16)&~15) * sizeof(struct uploadergroup*));
		if (FAILEDTOALLOC(memberof))
			return RET_ERROR_OOM;
		*memberof_p = memberof;
	}
	memberof[n] = group;
	memberof[n+1] = NULL;
	if (group->firstmemberat == 0)
		group->firstmemberat = lineno;
	if (group->emptyat != 0) {
		fprintf(stderr,
"%s:%lu: cannot add members to group '%s' marked empty in line %lu\n",
				filename, lineno, group->name, group->emptyat);
		return RET_ERROR;
	}
	return RET_OK;
}

static bool is_included_in(const struct uploadergroup *needle, const struct uploadergroup *chair) {
	const struct uploadergroup **g;

	if (needle->memberof == NULL)
		return false;
	for (g = needle->memberof ; *g != NULL ; g++) {
		if (*g == chair)
			return true;
		if (is_included_in(*g, chair))
			return true;
	}
	return false;
}

static inline retvalue parseuploaderline(char *buffer, const char *filename, size_t lineno, struct uploaders *u) {
	retvalue r;
	const char *p, *q;
	size_t l;
	struct upload_condition condition;

	l = strlen(buffer);
	if (l == 0)
		return RET_NOTHING;
	if (buffer[l-1] != '\n') {
		if (l >= 1024)
			fprintf(stderr, "%s:%lu:1024: Overlong line!\n",
					filename, (long)lineno);
		else
			fprintf(stderr, "%s:%lu:%lu: Unterminated line!\n",
					filename, (long)lineno, (long)l);
		return RET_ERROR;
	}
	do {
		buffer[--l] = '\0';
	} while (l > 0 && xisspace(buffer[l-1]));

	p = buffer;
	while (*p != '\0' && xisspace(*p))
		p++;
	if (*p == '\0' || *p == '#')
		return RET_NOTHING;

	if (strncmp(p, "group", 5) == 0 && (*p == '\0' || xisspace(p[5]))) {
		struct uploadergroup *group;

		p += 5;
		while (*p != '\0' && xisspace(*p))
			p++;
		r = find_group(&group, u, &p, filename, lineno, buffer);
		if (RET_WAS_ERROR(r))
			return r;
		while (*p != '\0' && xisspace(*p))
			p++;
		if (strncmp(p, "add", 3) == 0) {
			struct uploader *uploader;

			p += 3;
			while (*p != '\0' && xisspace(*p))
				p++;
			r = find_uploader(&uploader, u, p, filename,
					lineno, buffer);
			if (RET_WAS_ERROR(r))
				return r;
			r = include_group(group, &uploader->memberof,
					filename, lineno);
			if (RET_WAS_ERROR(r))
				return r;
			return RET_OK;
		} else if (strncmp(p, "contains", 8) == 0) {
			struct uploadergroup *member;

			p += 8;
			while (*p != '\0' && xisspace(*p))
				p++;
			q = p;
			r = find_group(&member, u, &q, filename,
					lineno, buffer);
			if (RET_WAS_ERROR(r))
				return r;
			if (group == member) {
				fprintf(stderr,
"%s:%lu: cannot add group '%s' to itself!\n",
						filename, (unsigned long)lineno,
						member->name);
				return RET_ERROR;
			}
			if (is_included_in(group, member)) {
				/* perhaps offer a winning coupon for the first
				 * one triggering this? */
				fprintf(stderr,
"%s:%lu: cannot add group '%s' to group '%s' as the later is already member of the former!\n",
						filename, (unsigned long)lineno,
						member->name, group->name);
				return RET_ERROR;
			}
			r = include_group(group, &member->memberof,
					filename, lineno);
			if (RET_WAS_ERROR(r))
				return r;
			if (member->firstusedat == 0)
				member->firstusedat = lineno;
			if (member->unusedat != 0) {
				fprintf(stderr,
"%s:%lu: cannot use group '%s' marked as unused in line %lu.\n",
						filename, (unsigned long)lineno,
						member->name, member->unusedat);
				return RET_ERROR;
			}
		} else if (strncmp(p, "empty", 5) == 0) {
			q = p + 5;
			if (group->emptyat != 0) {
				fprintf(stderr,
"%s:%lu: group '%s' marked as empty again (already happened in line %lu).\n",
						filename, (unsigned long)lineno,
						group->name, group->emptyat);
			}
			if (group->firstmemberat != 0) {
				fprintf(stderr,
"%s:%lu: group '%s' cannot be marked empty as it already has members (first in line %lu).\n",
						filename, (unsigned long)lineno,
						group->name,
						group->firstmemberat);
				return RET_ERROR;
			}
			group->emptyat = lineno;
		} else if (strncmp(p, "unused", 6) == 0) {
			q = p + 6;
			if (group->unusedat != 0) {
				fprintf(stderr,
"%s:%lu: group '%s' marked as unused again (already happened in line %lu).\n",
						filename, (unsigned long)lineno,
						group->name, group->unusedat);
			}
			if (group->firstusedat != 0) {
				fprintf(stderr,
"%s:%lu: group '%s' cannot be marked unused as it was already used (first in line %lu).\n",
						filename, (unsigned long)lineno,
						group->name,
						group->firstusedat);
				return RET_ERROR;
			}
			group->unusedat = lineno;
		} else {
			fprintf(stderr,
"%s:%lu:%u: missing 'add', 'contains', 'unused' or 'empty' keyword.\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			return RET_ERROR;
		}
		while (*q != '\0' && xisspace(*q))
			q++;
		if (*q != '\0') {
			fprintf(stderr,
"%s:%lu:%u: unexpected data at end of group statement!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			return RET_ERROR;
		}
		return RET_OK;
	}
	if (strncmp(p, "allow", 5) != 0 || !xisspace(p[5])) {
		fprintf(stderr,
"%s:%lu:%u: 'allow' or 'group' keyword expected! (no other statement has yet been implemented)\n",
					filename, (long)lineno,
					(int)(1 +p - buffer));
		return RET_ERROR;
	}
	p+=5;
	while (*p != '\0' && xisspace(*p))
		p++;
	r = parse_condition(filename, lineno, (1+p-buffer), &p, &condition);
	if (RET_WAS_ERROR(r))
		return r;
	while (*p != '\0' && xisspace(*p))
		p++;
	if (strncmp(p, "key", 3) == 0 && (p[3] == '\0' || xisspace(p[3]))) {
		struct uploader *uploader;

		p += 3;
		while (*p != '\0' && xisspace(*p))
			p++;
		r = find_uploader(&uploader, u, p, filename, lineno, buffer);
		assert (r != RET_NOTHING);
		if (RET_WAS_ERROR(r)) {
			uploadpermission_release(&condition);
			return r;
		}
		condition_add(&uploader->permissions, &condition);
	} else if (strncmp(p, "group", 5) == 0
			&& (p[5] == '\0' || xisspace(p[5]))) {
		struct uploadergroup *group;

		p += 5;
		while (*p != '\0' && xisspace(*p))
			p++;
		r = find_group(&group, u, &p, filename, lineno, buffer);
		assert (r != RET_NOTHING);
		if (RET_WAS_ERROR(r)) {
			uploadpermission_release(&condition);
			return r;
		}
		assert (group != NULL);
		while (*p != '\0' && xisspace(*p))
			p++;
		if (*p != '\0') {
			fprintf(stderr,
"%s:%lu:%u: unexpected data at end of group statement!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		if (group->firstusedat == 0)
			group->firstusedat = lineno;
		if (group->unusedat != 0) {
			fprintf(stderr,
"%s:%lu: cannot use group '%s' marked as unused in line %lu.\n",
					filename, (unsigned long)lineno,
					group->name, group->unusedat);
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		condition_add(&group->permissions, &condition);
	} else if (strncmp(p, "unsigned", 8) == 0
			&& (p[8]=='\0' || xisspace(p[8]))) {
		p+=8;
		if (*p != '\0') {
			fprintf(stderr,
"%s:%lu:%u: unexpected data after 'unsigned' statement!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		condition_add(&u->unsignedpermissions, &condition);
	} else if (strncmp(p, "any", 3) == 0 && xisspace(p[3])) {
		p+=3;
		while (*p != '\0' && xisspace(*p))
			p++;
		if (strncmp(p, "key", 3) != 0
				|| (p[3]!='\0' && !xisspace(p[3]))) {
			fprintf(stderr,
"%s:%lu:%u: 'key' keyword expected after 'any' keyword!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		p += 3;
		if (*p != '\0') {
			fprintf(stderr,
"%s:%lu:%u: unexpected data after 'any key' statement!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		condition_add(&u->anyvalidkeypermissions, &condition);
	} else if (strncmp(p, "anybody", 7) == 0
			&& (p[7] == '\0' || xisspace(p[7]))) {
		p+=7;
		while (*p != '\0' && xisspace(*p))
			p++;
		if (*p != '\0') {
			fprintf(stderr,
"%s:%lu:%u: unexpected data after 'anybody' statement!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
			uploadpermission_release(&condition);
			return RET_ERROR;
		}
		condition_add(&u->anybodypermissions, &condition);
	} else {
		fprintf(stderr,
"%s:%lu:%u: 'key', 'unsigned', 'anybody' or 'any key' expected!\n",
					filename, (long)lineno,
					(int)(1 + p - buffer));
		uploadpermission_release(&condition);
		return RET_ERROR;
	}
	return RET_OK;
}

static retvalue uploaders_load(/*@out@*/struct uploaders **list, const char *filename) {
	char *fullfilename = NULL;
	FILE *f;
	size_t lineno=0;
	char buffer[1025];
	struct uploaders *u;
	struct uploadergroup *g;
	retvalue r;

	if (filename[0] != '/') {
		fullfilename = calc_conffile(filename);
		if (FAILEDTOALLOC(fullfilename))
			return RET_ERROR_OOM;
		filename = fullfilename;
	}
	f = fopen(filename, "r");
	if (f == NULL) {
		int e = errno;
		fprintf(stderr, "Error opening '%s': %s\n",
				filename, strerror(e));
		free(fullfilename);
		return RET_ERRNO(e);
	}
	u = zNEW(struct uploaders);
	if (FAILEDTOALLOC(u)) {
		(void)fclose(f);
		free(fullfilename);
		return RET_ERROR_OOM;
	}
	/* reject by default */
	u->unsignedpermissions.type = uc_ALWAYS;
	u->anyvalidkeypermissions.type = uc_ALWAYS;
	u->anybodypermissions.type = uc_ALWAYS;

	while (fgets(buffer, 1024, f) != NULL) {
		lineno++;
		r = parseuploaderline(buffer, filename, lineno, u);
		if (RET_WAS_ERROR(r)) {
			(void)fclose(f);
			free(fullfilename);
			uploaders_free(u);
			return r;
		}
	}
	if (fclose(f) != 0) {
		int e = errno;
		fprintf(stderr, "Error reading '%s': %s\n",
				filename, strerror(e));
		free(fullfilename);
		uploaders_free(u);
		return RET_ERRNO(e);
	}
	for (g = u->groups ; g != NULL ; g = g->next) {
		if ((g->firstmemberat == 0 && g->emptyat == 0) &&
				g->firstusedat != 0)
			fprintf(stderr,
"%s:%lu: Warning: group '%s' gets used but never gets any members\n",
					filename, g->firstusedat, g->name);
		if ((g->firstusedat == 0 && g->unusedat == 0) &&
				g->firstmemberat != 0)
			fprintf(stderr,
"%s:%lu: Warning: group '%s' gets members but is not used in any rule\n",
					filename, g->firstmemberat, g->name);
	}
	free(fullfilename);
	*list = u;
	return RET_OK;
}

retvalue uploaders_get(/*@out@*/struct uploaders **list, const char *filename) {
	retvalue r;
	struct uploaders *u;
	size_t len;

	assert (filename != NULL);

	len = strlen(filename);
	u = uploaderslists;
	while (u != NULL && (u->filename_len != len ||
	                      memcmp(u->filename, filename, len) != 0))
		u = u->next;
	if (u == NULL) {
		r = uploaders_load(&u, filename);
		if (!RET_IS_OK(r))
			return r;
		assert (u != NULL);
		u->filename = strdup(filename);
		if (FAILEDTOALLOC(u->filename)) {
			uploaders_free(u);
			return RET_ERROR_OOM;
		}
		u->filename_len = len;
		u->next = uploaderslists;
		u->reference_count = 1;
		uploaderslists = u;
	} else
		u->reference_count++;
	*list = u;
	return RET_OK;
}
