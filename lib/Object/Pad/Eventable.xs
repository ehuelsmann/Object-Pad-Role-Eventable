/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Erik Huelsmann, 2023 -- ehuels@gmail.com
 *
 */
#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "XSParseKeyword.h"
#include "object_pad.h"


static int build_event(pTHX_ OP **out, XSParseKeywordPiece *args[], size_t nargs, void *hookdata)
{
  SV *name = args[0]->sv;

  ClassMeta *classmeta = get_compclassmeta();
  SV *eventsname = newSVpvf("%" SVf "::EVENTS", mop_class_get_name(classmeta));
  SAVEFREESV(eventsname);

  AV* events = get_av(SvPV_nolen(eventsname), GV_ADD | (SvFLAGS(eventsname) & SVf_UTF8));
  /* Put the event name in the @EVENTS variable in the package,
     since we have no way of accessing the class attribute values
     through the object_pad.h api for the moment. */
  av_push(events, name);

  return KEYWORD_PLUGIN_STMT;
}


static const struct XSParseKeywordHooks kwhooks_event = {
  .permit_hintkey = "Object::Pad::Eventable",

  .pieces = (const struct XSParseKeywordPieceType []) {
    XPK_IDENT,
    {0}
  },
  .build = &build_event,
};


static bool eventable_apply(pTHX_ ClassMeta *classmeta, SV *value, SV **attrdata_ptr, void *_funcdata)
{
  U32 flags = 0;
  SV *role_name = newSVpvs("Object::Pad::Eventable");
  SV *role_version = newSVpvs("0.000001");
  SV *eventsname = newSVpvf("%" SVf "::EVENTS", mop_class_get_name(classmeta));
  SAVEFREESV(eventsname);

  /* create @EVENTS in the class's package stash */
  (void)get_av(SvPV_nolen(eventsname), GV_ADD | (SvFLAGS(eventsname) & SVf_UTF8));

  /* The statement below causes an error: Can only apply a role to a class */
  /* mop_class_load_and_add_role(classmeta, role_name, role_version); */
  mop_class_apply_attribute(classmeta, "strict", sv_2mortal(newSVpvs("params")));

  return TRUE;
}

static void eventable_post_seal(pTHX_ ClassMeta *classmeta, SV *attrdata, void *_funcdata)
{
  dSP;

  ENTER;
  SAVETMPS;

  EXTEND(SP, 1);
  PUSHMARK(SP);
  PUSHs(mop_class_get_name(classmeta));
  PUTBACK;

  call_pv("Object::Pad::Eventable::_post_seal", G_VOID);

  FREETMPS;
  LEAVE;
}


static const struct ClassHookFuncs eventable_hooks = {
  .ver   = OBJECTPAD_ABIVERSION,
  .flags = 0,
  .permit_hintkey = "Object::Pad::Eventable/Eventable",

  .apply          = &eventable_apply,
  .post_seal      = &eventable_post_seal,
};


MODULE = Object::Pad::Eventable    PACKAGE = Object::Pad::Eventable

BOOT:
  boot_xs_parse_keyword(0.30);

  register_xs_parse_keyword("event", &kwhooks_event, NULL);
  register_class_attribute("Eventable", &eventable_hooks, NULL);
