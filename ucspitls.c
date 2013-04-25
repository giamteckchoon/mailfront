#include <unistd.h>
#include <stdlib.h>
#include <iobuf/iobuf.h>

int ucspitls(void)
{
  int fd;
  char *fdstr;
  int extrachars = 0;
  char c;

  /* STARTTLS must be the last command in a pipeline, otherwise we can
   * create a security risk (see CVE-2011-0411).  Close input and
   * check for any extra pipelined commands, so we can give an error
   * message.  Note that this will cause an error on the filehandle,
   * since we have closed it. */
  close(0);

  while (!ibuf_eof(&inbuf) && !ibuf_error(&inbuf)) {
    if (ibuf_getc(&inbuf, &c))
      ++extrachars;
  }

  if (!(fdstr=getenv("SSLCTLFD")))
    return 0;
  fd = atoi(fdstr);
  if (write(fd, "y", 1) < 1)
    return 0;

  if (!(fdstr=getenv("SSLREADFD")))
    return 0;
  fd = atoi(fdstr);
  if (dup2(fd,0) == -1)
    return 0;

  if (!(fdstr=getenv("SSLWRITEFD")))
    return 0;
  fd = atoi(fdstr);
  if (dup2(fd,1) == -1)
    return 0;

  /* Re-initialize stdin and clear input buffer */
  ibuf_init(&inbuf,0,0,IOBUF_NEEDSCLOSE, 4096);

  if (extrachars)
    return 0; /* Unexpected pipelined commands following STARTTLS */

  return 1;
}