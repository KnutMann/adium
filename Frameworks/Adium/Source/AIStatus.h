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

#import <Adium/AIStatusItem.h>

/* Keys used for storage and retrieval
 *
 * Five of them are gone with the auto-reply and with the editor's forced initial idle time: "Has
 * AutoReply", "AutoReply is Status Message", "AutoReply Message NSAttributedString", "Should Force
 * Initial Idle Time" and "Forced Initial Idle Time". They are not migrated away, because there is
 * nothing to migrate them to: they stay behind in the archived statusDict of everyone who ever
 * built a status of their own, where nothing reads them and a mutable dictionary does not mind
 * them. Whoever brings the auto-reply back should know that it would spring straight back to life
 * for those users - "Has AutoReply" was set for every away status by default, not by choice. */
#define	STATUS_STATUS_MESSAGE				@"Status Message NSAttributedString"
#define	STATUS_STATUS_NAME					@"Status Name"
#define STATUS_INVISIBLE					@"Invisible"
#define STATUS_MUTABILITY_TYPE				@"Mutability Type"
#define STATUS_MUTE_SOUNDS					@"Mute Sounds"
/* The value stays "Silence Growl" although Growl itself is long gone. It is a key inside the
 * archived statusDict of every status anyone ever built, so renaming the string would silently
 * drop the setting for everybody who had ever switched it on. Only the symbol moved. */
#define STATUS_SILENCE_NOTIFICATIONS		@"Silence Growl"
#define STATUS_SPECIAL_TYPE					@"Special Type"

typedef enum {
	AINoSpecialStatusType = 0,
	AINowPlayingSpecialStatusType
} AISpecialStatusType; 

@interface AIStatus : AIStatusItem {
	NSString *filteredStatusMessage;
}

+ (AIStatus *)status;
+ (AIStatus *)statusWithDictionary:(NSDictionary *)inDictionary;
+ (AIStatus *)statusOfType:(AIStatusType)inStatusType;

@property (readwrite, nonatomic, retain) NSAttributedString *statusMessage;

@property (readwrite, nonatomic, copy) NSString *statusMessageString;

- (void)setFilteredStatusMessage:(NSString *)inFilteredStatusMessage;

- (NSString *)statusMessageTooltipString;

@property (readwrite, nonatomic, retain) NSString *statusName;

- (void)setMutabilityType:(AIStatusMutabilityType)mutabilityType;

@property (readwrite, nonatomic) BOOL mutesSound;
@property (readwrite, nonatomic) BOOL silencesNotifications;
@property (readwrite, nonatomic) AISpecialStatusType specialStatusType;

@end
