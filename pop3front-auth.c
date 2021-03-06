/* pop3front-auth.c -- POP3 authentication front-end
 * Copyright (C) 2008  Bruce Guenter <bruce@untroubled.org> or FutureQuest, Inc.
 * Development of this program was sponsored by FutureQuest, Inc.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of version 2 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * Contact information:
 * FutureQuest Inc.
 * PO BOX 623127
 * Oviedo FL 32762-3127 USA
 * http://www.FutureQuest.net/
 * ossi@FutureQuest.net
 */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <cvm/v2client.h>
#include <iobuf/iobuf.h>
#include <str/iter.h>
#include <str/str.h>
#include <cvm/sasl.h>
#include "ucspitls.h"
#include "pop3.h"

const char program[] = "pop3front-auth";
const int authenticating = 1;

static const char* cvm;
static char** nextcmd;
static const char* domain;

static str user;

static unsigned user_count;
static unsigned user_max;
static unsigned auth_count;
static unsigned auth_max;

static struct sasl_auth saslauth = { .prefix = "+ " };

static int tls_available = 0;
static int auth_available = 1;

static void do_exec(void)
{
  if (!cvm_setugid() || !cvm_setenv())
    respond(err_internal);
  else {
    alarm(0);
    execvp(nextcmd[0], nextcmd);
    respond("-ERR Could not execute second stage");
  }
  _exit(1);
}

static void cmd_stls(void)
{
  if (!tls_available) {
    respond("-ERR STLS not available");
    return;
  }

  respond("+OK starting TLS negotiation");
  if (!ucspitls())
    exit(1);

  tls_available = 0;
  auth_available = 1;
  /* reset state */
  str_truncate(&user, 0);
}

static void cmd_auth_none(void)
{
  static str auth_resp;
  striter i;

  switch (sasl_auth_caps(&auth_resp)) {
  case 0:
    respond(ok);
    break;
  case 1:
    if (auth_resp.len <= 5) {
      respond(err_internal);
      return;
    }
    respond(ok);
    str_lcut(&auth_resp, 5);
    str_strip(&auth_resp);
    striter_loop(&i, &auth_resp, ' ') {
      obuf_write(&outbuf, i.startptr, i.len);
      obuf_puts(&outbuf, CRLF);
    }
    break;
  default:
    respond(err_internal);
    return;
  }
  respond(".");
}

static void cmd_auth(const str* s)
{
  int i;
  if ((i = sasl_auth1(&saslauth, s)) == 0) 
    do_exec();
  obuf_write(&outbuf, "-ERR ", 5);
  respond(sasl_auth_msg(&i));
  ++auth_count;
  if (auth_max > 0 && auth_count >= auth_max)
    exit(0);
}

static void cmd_user(const str* s)
{
  ++user_count;
  if (user_max > 0 && user_count > user_max) {
    respond("-ERR Too many USER commands issued");
    exit(0);
  }
  if (!auth_available)
    respond("-ERR Authentication not allowed without SSL/TLS");
  else if (!str_copy(&user, s))
    respond(err_internal);
  else
    respond(ok);
}

static void cmd_pass(const str* s)
{
  if (user.len == 0)
    respond("-ERR Send USER first");
  else {
    int cr;
    if ((cr = cvm_authenticate_password(cvm, user.s, domain, s->s, 1)) == 0)
      do_exec();
    str_truncate(&user, 0);
    if (cr == CVME_PERMFAIL)
      respond("-ERR Authentication failed");
    else
      respond(err_internal);
    ++auth_count;
    if (auth_max > 0 && auth_count >= auth_max)
      exit(0);
  }
}

static void cmd_quit(void)
{
  respond(ok);
  exit(0);
}

command commands[] = {
  { "CAPA", cmd_capa,      0,        0 },
  { "AUTH", cmd_auth_none, cmd_auth, 0 },
  { "PASS", 0,             cmd_pass, "PASS XXXXXXXX" },
  { "QUIT", cmd_quit,      0,        0 },
  { "USER", 0,             cmd_user, 0 },
  { "STLS", cmd_stls ,0,        0 },
  { 0,      0,             0,        0 }
};

int startup(int argc, char* argv[])
{
  static const char usage[] = "usage: pop3front-auth cvm program [args...]\n";
  const char* tmp;
  if ((tmp = getenv("MAXUSERCMD")) != 0)
    user_max = strtoul(tmp, 0, 10);
  if ((tmp = getenv("MAXAUTHFAIL")) != 0)
    auth_max = strtoul(tmp, 0, 10);
  if ((domain = cvm_ucspi_domain()) == 0)
    domain = "unknown";
  if (argc < 3) {
    obuf_putsflush(&errbuf, usage);
    return 0;
  }
  if (getenv("UCSPITLS"))
    tls_available = 1;
  if (getenv("AUTH_REQUIRES_TLS"))
    auth_available = 0;
  cvm = argv[1];
  nextcmd = argv+2;
  if (!sasl_auth_init(&saslauth)) {
    respond("-ERR Could not initialize SASL AUTH");
    return 0;
  }
  return 1;
}
