/*
 * fwverify - check the Ed25519 signature of a firmware release
 *
 *   fwverify FILE SIGFILE
 *
 * FILE is normally SHA256SUMS.txt of a release, SIGFILE the raw 64 byte
 * signature (SHA256SUMS.txt.sig) made by the release workflow. The public key
 * is compiled in (fw_sign.pub). Exit code 0 = valid, 1 = invalid, 2 = usage /
 * read error.
 *
 * Uses TweetNaCl (public domain). Only verification is needed, so the random
 * source TweetNaCl wants for key generation is never called.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tweetnacl.h"
#include "fw_sign_pub.h"

#define MAX_FILE (256 * 1024)

void randombytes(unsigned char *x, unsigned long long n)
{
    (void) x;
    (void) n;
    fprintf(stderr, "fwverify: randombytes must not be used\n");
    exit(2);
}

static long read_file(const char *path, unsigned char *buf, long max)
{
    FILE *f = fopen(path, "rb");
    long n;

    if (f == NULL)
        return -1;
    n = (long) fread(buf, 1, max + 1, f);
    fclose(f);
    if (n > max)
        return -1;
    return n;
}

int main(int argc, char **argv)
{
    unsigned char sig[crypto_sign_BYTES + 1];
    unsigned char *sm, *m;
    unsigned long long mlen;
    long n, s;
    int ret;

    if (argc != 3) {
        fprintf(stderr, "usage: %s FILE SIGFILE\n", argv[0]);
        return 2;
    }

    sm = malloc(crypto_sign_BYTES + MAX_FILE + 1);
    m = malloc(crypto_sign_BYTES + MAX_FILE + 1);
    if (sm == NULL || m == NULL) {
        fprintf(stderr, "fwverify: out of memory\n");
        return 2;
    }

    s = read_file(argv[2], sig, crypto_sign_BYTES);
    if (s != crypto_sign_BYTES) {
        fprintf(stderr, "fwverify: signature must be %d bytes\n", crypto_sign_BYTES);
        return 2;
    }
    n = read_file(argv[1], sm + crypto_sign_BYTES, MAX_FILE);
    if (n < 0) {
        fprintf(stderr, "fwverify: cannot read %s\n", argv[1]);
        return 2;
    }

    /* TweetNaCl works on "signature || message" */
    memcpy(sm, sig, crypto_sign_BYTES);
    ret = crypto_sign_open(m, &mlen, sm, (unsigned long long) n + crypto_sign_BYTES, fw_sign_pub);
    if (ret != 0) {
        fprintf(stderr, "fwverify: INVALID signature\n");
        return 1;
    }
    printf("fwverify: signature ok\n");
    return 0;
}
