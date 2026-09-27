/* Does picomemo hold up on this machine?
 *
 * Before a single line of XMPP comes into being, the foundation has to stand: two participants
 * each build themselves a key store, one of them builds a session out of the other's bundle, and
 * then one message goes across and one comes back. That checks X3DH, the double ratchet and
 * AES-GCM in one pass, and on arm64 against the same OpenSSL we ship anyway.
 *
 * It is also checked that a key store survives being saved and loaded back, because that is
 * exactly what every start of the program will do later on.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "omemo0.h"

static int failures = 0;
static void check(const char *name, int ok, const char *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail : "");
	if (!ok) failures++;
}

/* Skipped keys: one place is enough here, a real client puts them away */
static struct omemo0MessageKey skipped[64];
static int skippedCount = 0;

static int loadMessageKey(struct omemo0Session *s, struct omemo0MessageKey *sk)
{
	for (int i = 0; i < skippedCount; i++)
		if (!memcmp(skipped[i].dh, sk->dh, sizeof(sk->dh)) && skipped[i].nr == sk->nr) {
			memcpy(sk, &skipped[i], sizeof(*sk));
			return 0;
		}
	return 1;			//not found
}

static int storeMessageKey(struct omemo0Session *s, const struct omemo0MessageKey *sk, uint64_t n)
{
	if (skippedCount < (int)(sizeof(skipped) / sizeof(skipped[0])))
		memcpy(&skipped[skippedCount++], sk, sizeof(*sk));
	return 0;
}

static int randomBytes(void *p, size_t n)
{
	FILE *urandom = fopen("/dev/urandom", "rb");
	if (!urandom)
		return 1;
	size_t got = fread(p, 1, n, urandom);
	fclose(urandom);
	return (got == n) ? 0 : 1;
}

/*! One message from one to the other, over a session that already stands */
static int sayAndHear(struct omemo0Session *from, struct omemo0Store *fromStore,
					  struct omemo0Session *to, struct omemo0Store *toStore,
					  const char *text, int isFirst)
{
	//The payload key both sides are meant to share
	uint8_t key[32];
	if (randomBytes(key, sizeof(key)))
		return 0;

	struct omemo0KeyMessage wrapped;
	memset(&wrapped, 0, sizeof(wrapped));
	if (omemo0EncryptKey(from, &wrapped, key, sizeof(key)))
		return 0;

	uint8_t heard[32];
	size_t heardn = sizeof(heard);
	if (omemo0DecryptKey(to, toStore, heard, &heardn, wrapped.isprekey, wrapped.p, wrapped.n))
		return 0;

	if (heardn != sizeof(key) || memcmp(key, heard, sizeof(key)))
		return 0;

	/* And with it the actual text. The old form does not pad, it takes an initialisation
	 * vector of its own and hands the payload key back. */
	size_t textn = strlen(text);
	uint8_t *cipher = calloc(1, textn + 32);
	uint8_t *plain = calloc(1, textn + 32);
	uint8_t payloadKey[32], iv[12];
	int ok = 1;

	if (omemo0EncryptMessage(cipher, payloadKey, iv, (const uint8_t *)text, textn))
		ok = 0;

	//And the counter check: the same key has to give the same text back
	if (ok && omemo0DecryptMessage(plain, payloadKey, sizeof(payloadKey), iv, cipher, textn))
		ok = 0;
	if (ok && memcmp(plain, text, textn))
		ok = 0;

	free(cipher);
	free(plain);
	return ok;
}

int main(void)
{
	omemo0SetCallbacks(loadMessageKey, storeMessageKey, randomBytes);

	struct omemo0Store alice, bob;
	memset(&alice, 0, sizeof(alice));
	memset(&bob, 0, sizeof(bob));

	check("Alice builds herself a key store", omemo0SetupStore(&alice) == 0, NULL);
	check("Bob does too", omemo0SetupStore(&bob) == 0, NULL);
	check("and both have an identity",
		  alice.init && bob.init &&
		  memcmp(alice.identity.pub, bob.identity.pub, sizeof(alice.identity.pub)) != 0, NULL);

	//The store has to survive being written out and loaded back, which every start does later
	size_t storeSize = omemo0GetSerializedStoreSize(&alice);
	uint8_t *saved = malloc(storeSize);
	omemo0SerializeStore(saved, &alice);

	struct omemo0Store restored;
	memset(&restored, 0, sizeof(restored));
	check("A saved store can be loaded back",
		  omemo0DeserializeStore(saved, storeSize, &restored) == 0, NULL);
	check("and carries the same identity",
		  memcmp(alice.identity.prv, restored.identity.prv, sizeof(alice.identity.prv)) == 0, NULL);
	free(saved);

	/* And from here on Alice goes on with the store that was LOADED BACK. Comparing the keys
	 * alone proves nothing: what counts is whether a session still comes about with them
	 * afterwards, and that is exactly what every start of the program does. */
	alice = restored;

	//Alice builds a session out of Bob's bundle
	omemo0SerializedKey bobIdentity, bobSigned, bobPre;
	omemo0SerializeKey(bobIdentity, bob.identity.pub);
	omemo0SerializeKey(bobSigned, bob.cursignedprekey.kp.pub);
	omemo0SerializeKey(bobPre, bob.prekeys[0].kp.pub);

	struct omemo0Session aliceToBob, bobToAlice;
	memset(&aliceToBob, 0, sizeof(aliceToBob));
	memset(&bobToAlice, 0, sizeof(bobToAlice));

	int started = omemo0InitiateSession(&aliceToBob, &alice,
									   bob.cursignedprekey.sig, bobSigned, bobIdentity, bobPre,
									   bob.cursignedprekey.id, bob.prekeys[0].id);
	check("Alice builds a session out of Bob's bundle", started == 0, NULL);

	check("A message from Alice arrives at Bob",
		  sayAndHear(&aliceToBob, &alice, &bobToAlice, &bob, "Hello Bob", 1), NULL);

	check("and the answer from Bob at Alice",
		  sayAndHear(&bobToAlice, &bob, &aliceToBob, &alice, "Hello Alice", 0), NULL);

	check("The ratchet moved on while doing so",
		  aliceToBob.state.ns > 0 || aliceToBob.state.nr > 0, NULL);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
}
