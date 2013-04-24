#ifndef PLCB_MULTI_H_
#define PLCB_MULTI_H_

/**
 * Accepts either an array of arrays, or an array of strings
 */
SV*
PLCB_multi_get_common(SV *self,
                      AV *speclist,
                      int cmd,
                      PLCBA_cookie_t *async_cookie);

SV*
PLCB_multi_set_common(SV *self,
                      AV *speclist,
                      int cmd,
                      PLCBA_cookie_t *async_cookie);

SV* PLCB_multi_arithmetic_common(SV *self,
                                 AV *speclist,
                                 int cmd,
                                 PLCBA_cookie_t *async_cookie);

SV*
PLCB_multi_remove(SV *self, AV *speclist, PLCBA_cookie_t *async_cookie);


/**
 * The following two are not implemented yet
 */
SV*
PLCB_observe_multi(SV *self, AV *speclist, PLCBA_cookie_t *async_cookie);

SV*
PLCB_unlock_multi(SV *self, AV *speclist, PLCBA_cookie_t *async_cookie);

#endif
