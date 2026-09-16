/* Traegt picomemo auf diesem Rechner?
 *
 * Bevor eine Zeile XMPP entsteht, muss das Fundament stehen: zwei Teilnehmer legen sich je
 * einen Schluesselvorrat an, der eine baut aus dem Buendel des anderen eine Sitzung auf, und
 * dann geht eine Nachricht hin und eine zurueck. Das prueft X3DH, die Doppelratsche und
 * AES-GCM in einem Durchgang, und zwar auf arm64 gegen dieselbe OpenSSL, die wir ohnehin
 * ausliefern.
 *
 * Geprueft wird ausserdem, dass ein Schluesselvorrat das Speichern und Zurueckladen ueberlebt,
 * denn genau das wird spaeter jeder Programmstart tun.
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

/* Uebersprungene Schluessel: hier reicht ein Platz, ein echter Client legt sie weg */
static struct omemo0MessageKey skipped[64];
static int skippedCount = 0;

static int loadMessageKey(struct omemo0Session *s, struct omemo0MessageKey *sk)
{
	for (int i = 0; i < skippedCount; i++)
		if (!memcmp(skipped[i].dh, sk->dh, sizeof(sk->dh)) && skipped[i].nr == sk->nr) {
			memcpy(sk, &skipped[i], sizeof(*sk));
			return 0;
		}
	return 1;			//nicht gefunden
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

/*! Eine Nachricht von einem zum anderen, ueber eine schon stehende Sitzung */
static int sayAndHear(struct omemo0Session *from, struct omemo0Store *fromStore,
					  struct omemo0Session *to, struct omemo0Store *toStore,
					  const char *text, int isFirst)
{
	//Der Nutzschluessel, den beide Seiten teilen sollen
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

	/* Und damit der eigentliche Text. Die alte Fassung polstert nicht, sie nimmt einen
	 * eigenen Initialisierungsvektor und liefert den Nutzschluessel zurueck. */
	size_t textn = strlen(text);
	uint8_t *cipher = calloc(1, textn + 32);
	uint8_t *plain = calloc(1, textn + 32);
	uint8_t payloadKey[32], iv[12];
	int ok = 1;

	if (omemo0EncryptMessage(cipher, payloadKey, iv, (const uint8_t *)text, textn))
		ok = 0;

	//Und die Gegenprobe: derselbe Schluessel muss denselben Text zurueckgeben
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

	check("Alice legt sich einen Schluesselvorrat an", omemo0SetupStore(&alice) == 0, NULL);
	check("Bob auch", omemo0SetupStore(&bob) == 0, NULL);
	check("und beide haben eine Identitaet",
		  alice.init && bob.init &&
		  memcmp(alice.identity.pub, bob.identity.pub, sizeof(alice.identity.pub)) != 0, NULL);

	//Der Vorrat muss das Wegschreiben und Zurueckladen ueberleben, das tut spaeter jeder Start
	size_t storeSize = omemo0GetSerializedStoreSize(&alice);
	uint8_t *saved = malloc(storeSize);
	omemo0SerializeStore(saved, &alice);

	struct omemo0Store restored;
	memset(&restored, 0, sizeof(restored));
	check("Ein gespeicherter Vorrat laesst sich zurueckladen",
		  omemo0DeserializeStore(saved, storeSize, &restored) == 0, NULL);
	check("und traegt dieselbe Identitaet",
		  memcmp(alice.identity.prv, restored.identity.prv, sizeof(alice.identity.prv)) == 0, NULL);
	free(saved);

	/* Und von hier an rechnet Alice mit dem ZURUECKGELADENEN Vorrat weiter. Ein Vergleich der
	 * Schluessel allein beweist naemlich nichts: was zaehlt, ist ob damit hinterher noch eine
	 * Sitzung zustande kommt, und genau das tut jeder Programmstart. */
	alice = restored;

	//Alice baut aus Bobs Buendel eine Sitzung auf
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
	check("Alice baut aus Bobs Buendel eine Sitzung auf", started == 0, NULL);

	check("Eine Nachricht von Alice kommt bei Bob an",
		  sayAndHear(&aliceToBob, &alice, &bobToAlice, &bob, "Hallo Bob", 1), NULL);

	check("und die Antwort von Bob bei Alice",
		  sayAndHear(&bobToAlice, &bob, &aliceToBob, &alice, "Hallo Alice", 0), NULL);

	check("Die Ratsche ist dabei weitergelaufen",
		  aliceToBob.state.ns > 0 || aliceToBob.state.nr > 0, NULL);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
}
