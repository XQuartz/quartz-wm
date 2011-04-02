/* x-list.h -- simple list type
 *
 * Copyright (c) 2002-2010 Apple Inc. All Rights Reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#ifndef X_LIST_H
#define X_LIST_H 1

/* This is just a cons. */

typedef struct x_list_struct x_list;

struct x_list_struct {
    void *data;
    x_list *next;
};

#ifndef X_PFX
# define X_PFX(x) x_ ## x
#endif

#ifndef X_EXTERN
# define X_EXTERN __private_extern__
#endif

X_EXTERN void X_PFX (list_free_1) (x_list *node);
X_EXTERN x_list *X_PFX (list_prepend) (x_list *lst, void *data);

X_EXTERN x_list *X_PFX (list_append) (x_list *lst, void *data);
X_EXTERN x_list *X_PFX (list_remove) (x_list *lst, void *data);
X_EXTERN void X_PFX (list_free) (x_list *lst);
X_EXTERN x_list *X_PFX (list_pop) (x_list *lst, void **data_ret);

X_EXTERN x_list *X_PFX (list_copy) (x_list *lst);
X_EXTERN x_list *X_PFX (list_reverse) (x_list *lst);
X_EXTERN x_list *X_PFX (list_find) (x_list *lst, void *data);
X_EXTERN x_list *X_PFX (list_nth) (x_list *lst, int n);
X_EXTERN x_list *X_PFX (list_filter) (x_list *src,
				      int (*pred) (void *item, void *data),
				      void *data);
X_EXTERN x_list *X_PFX (list_map) (x_list *src,
				   void *(*fun) (void *item, void *data),
				   void *data);

X_EXTERN unsigned int X_PFX (list_length) (x_list *lst);
X_EXTERN void X_PFX (list_foreach) (x_list *lst, void (*fun)
				    (void *data, void *user_data),
				    void *user_data);

X_EXTERN x_list *X_PFX (list_sort) (x_list *lst, int (*less) (const void *,
							    const void *));

#endif /* X_LIST_H */
