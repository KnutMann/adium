/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AIOMEMOMedia.h"
#import <openssl/evp.h>

/*
 * The fragment of an aesgcm:// address is the number used once followed by the key, written as
 * hexadecimal. Both lengths vary between clients and both are accepted: twelve bytes is what
 * everything current uses for the first, sixteen is the older reading, and the key is sixteen or
 * thirty two bytes depending on whether the sender chose a 128 or 256 bit cipher.
 */
#define TAG_LENGTH		16

static BOOL lengthsMakeSense(NSUInteger vector, NSUInteger key)
{
	return (vector == 12 || vector == 16) && (key == 16 || key == 32);
}

/*!
 * @brief Read an even number of hexadecimal digits into bytes
 */
static NSData *bytesFromHex(NSString *hex)
{
	NSUInteger length = [hex length];
	if (length < 2 || (length % 2)) return nil;

	NSMutableData *bytes = [NSMutableData dataWithLength:(length / 2)];
	uint8_t *out = [bytes mutableBytes];

	for (NSUInteger index = 0; index < length; index += 2) {
		unsigned int one = 0;
		NSString *pair = [hex substringWithRange:NSMakeRange(index, 2)];

		//Anything that is not a hexadecimal digit makes the whole thing not a key
		NSScanner *reader = [NSScanner scannerWithString:pair];
		if (![reader scanHexInt:&one] || ![reader isAtEnd]) return nil;

		out[index / 2] = (uint8_t)one;
	}
	return bytes;
}

BOOL AIOMEMOMediaReadLink(NSString *link, NSString **address, NSData **ivAndKey)
{
	NSString *text = [link stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (![[text lowercaseString] hasPrefix:@"aesgcm://"]) return NO;

	NSRange hash = [text rangeOfString:@"#" options:NSBackwardsSearch];
	if (hash.location == NSNotFound) return NO;

	NSData *material = bytesFromHex([text substringFromIndex:(hash.location + 1)]);
	if (!material) return NO;

	/* Which part is the number used once and which the key is decided by the total length, since
	 * the fragment says only how much there is and not where the join sits. */
	NSUInteger total = [material length];
	NSUInteger vector = 0;

	if (lengthsMakeSense(12, total - 12)) vector = 12;
	else if (lengthsMakeSense(16, total - 16)) vector = 16;
	else return NO;

	if (address) {
		NSString *withoutKey = [text substringToIndex:hash.location];
		*address = [@"https://" stringByAppendingString:
					[withoutKey substringFromIndex:[@"aesgcm://" length]]];
	}
	if (ivAndKey) *ivAndKey = material;

	//Kept together so that the caller cannot pair one message's key with another's file
	(void)vector;
	return YES;
}

NSData *AIOMEMOMediaDecrypt(NSData *encrypted, NSData *ivAndKey)
{
	if (![encrypted length] || ![ivAndKey length]) return nil;

	NSUInteger total = [ivAndKey length];
	NSUInteger vectorLength = (total == 12 + 16 || total == 12 + 32) ? 12 : 16;
	NSUInteger keyLength = total - vectorLength;

	if (!lengthsMakeSense(vectorLength, keyLength)) return nil;

	/* The last sixteen bytes are the tag. A file shorter than that is not a short file, it is
	 * not one of ours. */
	if ([encrypted length] <= TAG_LENGTH) return nil;

	const uint8_t *material = [ivAndKey bytes];
	const uint8_t *vector = material;
	const uint8_t *key = material + vectorLength;

	const uint8_t *cipher = [encrypted bytes];
	NSUInteger cipherLength = [encrypted length] - TAG_LENGTH;
	const uint8_t *tag = cipher + cipherLength;

	NSMutableData *plain = [NSMutableData dataWithLength:cipherLength];
	if (!plain) return nil;

	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	if (!ctx) return nil;

	const EVP_CIPHER *cipherKind = (keyLength == 32) ? EVP_aes_256_gcm() : EVP_aes_128_gcm();
	NSData *result = nil;
	int written = 0;

	if (EVP_DecryptInit_ex(ctx, cipherKind, NULL, NULL, NULL) == 1 &&
		EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)vectorLength, NULL) == 1 &&
		EVP_DecryptInit_ex(ctx, NULL, NULL, key, vector) == 1 &&
		EVP_DecryptUpdate(ctx, [plain mutableBytes], &written, cipher, (int)cipherLength) == 1 &&
		written == (int)cipherLength &&
		EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, TAG_LENGTH, (void *)tag) == 1) {

		int trailing = 0;

		/* This is the line that decides whether the file is genuine. Everything above merely
		 * produced bytes; only here does the tag get checked, and a file that fails it has
		 * either been damaged or interfered with. Either way it did not arrive. */
		if (EVP_DecryptFinal_ex(ctx, [plain mutableBytes] + written, &trailing) == 1)
			result = plain;
	}

	EVP_CIPHER_CTX_free(ctx);
	return result;
}

NSData *AIOMEMOMediaEncrypt(NSData *plain, NSData **ivAndKey)
{
	if (![plain length]) return nil;

	/* Twelve bytes of number used once and a 256 bit key, which is what every client that
	 * reads these expects to find, and what the older sixteen byte form was replaced by. */
	NSMutableData *material = [NSMutableData dataWithLength:(12 + 32)];
	if (!material) return nil;

	arc4random_buf([material mutableBytes], [material length]);

	const uint8_t *vector = [material bytes];
	const uint8_t *key = [material bytes] + 12;

	NSMutableData *out = [NSMutableData dataWithLength:([plain length] + TAG_LENGTH)];
	if (!out) return nil;

	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	if (!ctx) return nil;

	NSData *result = nil;
	int written = 0, trailing = 0;
	uint8_t *into = [out mutableBytes];

	if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1 &&
		EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) == 1 &&
		EVP_EncryptInit_ex(ctx, NULL, NULL, key, vector) == 1 &&
		EVP_EncryptUpdate(ctx, into, &written, [plain bytes], (int)[plain length]) == 1 &&
		written == (int)[plain length] &&
		EVP_EncryptFinal_ex(ctx, into + written, &trailing) == 1 &&
		trailing == 0 &&
		EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, TAG_LENGTH, into + written) == 1) {

		result = out;
		if (ivAndKey) *ivAndKey = material;
	}

	EVP_CIPHER_CTX_free(ctx);
	return result;
}

NSString *AIOMEMOMediaMakeLink(NSString *httpsAddress, NSData *ivAndKey)
{
	if (![httpsAddress hasPrefix:@"https://"] || ![ivAndKey length]) return nil;

	NSMutableString *hex = [NSMutableString stringWithCapacity:([ivAndKey length] * 2)];
	const uint8_t *bytes = [ivAndKey bytes];
	for (NSUInteger index = 0; index < [ivAndKey length]; index++)
		[hex appendFormat:@"%02x", bytes[index]];

	return [NSString stringWithFormat:@"aesgcm://%@#%@",
			[httpsAddress substringFromIndex:[@"https://" length]], hex];
}

NSString *AIOMEMOMediaExtensionOf(NSString *link)
{
	/* Read off the text rather than through NSURL, which does not treat aesgcm as a scheme it
	 * knows and hands back nothing useful for one. */
	NSString *text = link;

	NSRange hash = [text rangeOfString:@"#" options:NSBackwardsSearch];
	if (hash.location != NSNotFound) text = [text substringToIndex:hash.location];

	NSRange question = [text rangeOfString:@"?" options:NSBackwardsSearch];
	if (question.location != NSNotFound) text = [text substringToIndex:question.location];

	NSString *last = [[text componentsSeparatedByString:@"/"] lastObject];
	NSRange dot = [last rangeOfString:@"." options:NSBackwardsSearch];
	if (dot.location == NSNotFound) return nil;

	return [[last substringFromIndex:(dot.location + 1)] lowercaseString];
}
