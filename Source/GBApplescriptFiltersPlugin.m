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

#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import "ESApplescriptabilityController.h"
#import "GBApplescriptFiltersPlugin.h"
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/MVMenuButton.h>
#import <Adium/AIContentObject.h>
#import <Adium/AIHTMLDecoder.h>

#import <sys/errno.h>
#import <string.h>

#define TITLE_INSERT_SCRIPT		AILocalizedString(@"Insert Script",nil)
#define SCRIPT_BUNDLE_EXTENSION	@"AdiumScripts"
#define SCRIPTS_PATH_NAME		@"Scripts"
#define SCRIPT_EXTENSION		@"scpt"
#define	SCRIPT_IDENTIFIER		@"InsertScript"

#define SCRIPT_TIMEOUT			30

/* One message is filtered by running one script per keyword occurrence, each run looking at the
 * result of the last. A script whose output contains its own keyword would keep that going forever,
 * so the chain gets a ceiling. It is set well above anything a person would type on purpose.
 */
#define SCRIPT_CHAIN_LIMIT		32

@interface GBApplescriptFiltersPlugin ()
- (NSArray *)_argumentsFromString:(NSString *)inString forScript:(NSMutableDictionary *)scriptDict;
- (void)buildScriptMenu;
- (void)_appendScripts:(NSArray *)scripts toMenu:(NSMenu *)menu;
- (void)registerToolbarItem;
- (void)xtrasChanged:(NSNotification *)notification;
- (IBAction)selectScript:(id)sender;
- (void)applescriptDidRun:(id)userInfo resultString:(NSString *)resultString;
- (IBAction)dummyTarget:(id)sender;

- (BOOL)_replaceKeyword:(NSString *)keyword
			 withScript:(NSMutableDictionary *)infoDict
			   inString:(NSString *)inString
	 inAttributedString:(NSMutableAttributedString *)attributedString
				context:(id)context
			   uniqueID:(unsigned long long)uniqueID;

- (BOOL)_executeScript:(NSMutableDictionary *)infoDict
		 withArguments:(NSArray *)arguments
		 forAttributedString:(NSMutableAttributedString *)attributedString
		  keywordRange:(NSRange)keywordRange
			   context:(id)context
			  uniqueID:(unsigned long long)uniqueID;

- (void)_armWatchdogForUniqueID:(unsigned long long)uniqueID
			   attributedString:(NSMutableAttributedString *)attributedString;
- (BOOL)_consumeRunForUniqueID:(unsigned long long)uniqueID;
- (void)_forgetFiltration:(unsigned long long)uniqueID;
- (void)scriptRunTimedOut:(NSTimer *)timer;
@end

NSInteger _scriptTitleSort(id scriptA, id scriptB, void *context);
NSInteger _scriptKeywordLengthSort(id scriptA, id scriptB, void *context);

/*!
 * @class GBApplescriptFiltersPlugin
 * @brief Filter component to allow .AdiumScripts applescript-based filters for outgoing messages
 */
@implementation GBApplescriptFiltersPlugin

/*!
 * @brief Install
 */
- (void)installPlugin
{
	//User scripts
	[adium createResourcePathForName:@"Scripts"];
	
	//We have an array of scripts for building the menu, and a dictionary of scripts used for the actual substition
	scriptArray = nil;
	flatScriptArray = nil;
	
	//Prepare our script menu item (which will have the Scripts menu as its submenu)
	scriptMenuItem = [[NSMenuItem alloc] initWithTitle:TITLE_INSERT_SCRIPT 
												target:self
												action:@selector(dummyTarget:)
										 keyEquivalent:@""];

	//Perform substitutions on outgoing content; we may be slow, so register as a delayed content filter
	[adium.contentController registerDelayedContentFilter:self 
													 ofType:AIFilterContent
												  direction:AIFilterOutgoing];
	
	//Observe for installation of new scripts
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(xtrasChanged:)
									   name:AIXtrasDidChangeNotification
									 object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(toolbarWillAddItem:)
												 name:NSToolbarWillAddItemNotification
											   object:nil];	
	
	//Start building the script menu
	scriptMenu = nil;
	[self buildScriptMenu]; //this also sets the submenu for the menu item.
	
	[adium.menuController addMenuItem:scriptMenuItem toLocation:LOC_Edit_Additions];
	
	contextualScriptMenuItem = [scriptMenuItem copy];
	[adium.menuController addContextualMenuItem:contextualScriptMenuItem toLocation:Context_TextView_Edit];
}

/*!
 * @brief Uninstall
 *
 * This is the only place where a watchdog which is still ticking can actually be stopped: an armed
 * NSTimer retains its target, so as long as one exists this plugin cannot be deallocated at all and
 * -dealloc will never come around to clean anything up.
 */
- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	/* Without this the filter would stay registered on a plugin nobody owns any more -- and worse,
	 * once it is gone from the delayed list it is no longer skipped on the synchronous path, where
	 * its return value is thrown away.
	 */
	[adium.contentController unregisterDelayedContentFilter:self];

	for (NSTimer *timer in [pendingScriptRuns allValues]) {
		[timer invalidate];
	}
	[pendingScriptRuns removeAllObjects];
	[scriptChainDepth removeAllObjects];
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	//Belt and braces; a watchdog which is still armed holds us up long enough that we never get here
	for (NSTimer *timer in [pendingScriptRuns allValues]) {
		[timer invalidate];
	}
}

/*!
 * @brief Xtras changes
 *
 * If the scripts xtras changed, rebuild our menus.
 */
- (void)xtrasChanged:(NSNotification *)notification
{
	if ([[notification object] caseInsensitiveCompare:@"AdiumScripts"] == NSOrderedSame) {
		[self buildScriptMenu];
				
		[self registerToolbarItem];
		
		//Update our toolbar item's menu
		//[self toolbarWillAddItem:nil];
	}
}


//Script Loading -------------------------------------------------------------------------------------------------------
#pragma mark Script Loading
/*!
 * @brief Load our scripts
 *
 * This will clear out and then load from available scripts (external and internal) into flatScriptArray and scriptArray.
 */
- (void)loadScripts
{
	//
	scriptArray = [[NSMutableArray alloc] init];
	flatScriptArray = [[NSMutableArray alloc] init];
	
	// Load scripts
	for (NSString *filePath in [adium allResourcesForName:@"Scripts" withExtensions:SCRIPT_BUNDLE_EXTENSION]) {
		NSBundle		*scriptBundle;

		if ((scriptBundle = [NSBundle bundleWithPath:filePath])) {
			NSString		*scriptsSetName;
			NSDictionary	*infoDict = [NSDictionary dictionaryWithContentsOfFile:[[scriptBundle bundlePath] stringByAppendingPathComponent:@"Info.plist"]];
			if (!infoDict) infoDict= [scriptBundle infoDictionary];

			NSDictionary	*localizedInfoDict = [scriptBundle localizedInfoDictionary];

			//Get the name of the set these scripts will go into
			scriptsSetName = [localizedInfoDict objectForKey:@"Set"];
			if (!scriptsSetName) scriptsSetName = [infoDict objectForKey:@"Set"];

			//Now enumerate each script the bundle claims as its own
			for (NSDictionary *scriptDict in [infoDict objectForKey:@"Scripts"]) {
				NSString		*scriptFileName, *scriptFilePath, *keyword, *title;
				NSArray			*arguments;
				NSNumber		*prefixOnlyNumber;
				
				if ((scriptFileName = [scriptDict objectForKey:@"File"]) &&
					(scriptFilePath = [scriptBundle pathForResource:scriptFileName
															 ofType:SCRIPT_EXTENSION])) {
					
					keyword = [scriptDict objectForKey:@"Keyword"];
					title = [scriptDict objectForKey:@"Title"];

					//The keywords titles are keyed by their English version in the localized info dict
					NSString *localizedKeyword = [localizedInfoDict objectForKey:keyword];
					if (localizedKeyword) keyword = localizedKeyword;

					NSString *localizedTitle = [localizedInfoDict objectForKey:title];
					if (localizedTitle) title = localizedTitle;

					if (keyword && [keyword length] && title && [title length]) {
						NSMutableDictionary	*newInfoDict;
						
						arguments = [[scriptDict objectForKey:@"Arguments"] componentsSeparatedByString:@","];
						
						//Assume "Prefix Only" is NO unless told otherwise or the keyword starts with '/'
						prefixOnlyNumber = [scriptDict objectForKey:@"Prefix Only"];
						if (!prefixOnlyNumber) {
							prefixOnlyNumber = [NSNumber numberWithBool:[keyword hasPrefix:@"/"]];
						}

						newInfoDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
							scriptFilePath, @"Path", keyword, @"Keyword", title, @"Title", 
							prefixOnlyNumber, @"PrefixOnly", nil];
						
						//The bundle may not be part of (or for defining) a set of scripts
						if (scriptsSetName) {
							[newInfoDict setObject:scriptsSetName forKey:@"Set"];
						}
						//Arguments may be nil
						if (arguments) {
							[newInfoDict setObject:arguments forKey:@"Arguments"];
						}
						
						//Place the entry in our script arrays
						[scriptArray addObject:newInfoDict];
						[flatScriptArray addObject:newInfoDict];
						
						//Scripts must always be updated via polling
						[adium.contentController registerFilterStringWhichRequiresPolling:keyword];
					}
				}
			}
		} else {
			NSLog(@"Warning: Could not load Adium script bundle at %@",filePath);
		}
	}
}


//Script Menu ----------------------------------------------------------------------------------------------------------
#pragma mark Script Menu
/*!
 * @brief Build the script menu
 *
 * Loads the scrpts as necessary, sorts them, then builds menus for the menu bar, the contextual menu,
 * and the toolbar item.
 */
- (void)buildScriptMenu
{
	[self loadScripts];
	
	//Sort the scripts
	[scriptArray sortUsingFunction:_scriptTitleSort context:nil];
	[flatScriptArray sortUsingFunction:_scriptKeywordLengthSort context:nil];
	
	//Build the menu
	scriptMenu = [[NSMenu alloc] initWithTitle:TITLE_INSERT_SCRIPT];
	[self _appendScripts:scriptArray toMenu:scriptMenu];
	[scriptMenuItem setSubmenu:scriptMenu];
	[contextualScriptMenuItem setSubmenu:[scriptMenu copy]];
		
	[self registerToolbarItem];
}

/*!
 * @brief Sort first by set, then by title within sets
 */
NSInteger _scriptTitleSort(id scriptA, id scriptB, void *context) {
	NSComparisonResult result;
	
	NSString	*setA = [scriptA objectForKey:@"Set"];
	NSString	*setB = [scriptB objectForKey:@"Set"];
	
	if (setA && setB) {
		
		//If both are within sets, sort by set; if they are within the same set, sort by title
		if ((result = [setA caseInsensitiveCompare:setB]) == NSOrderedSame) {
			result = [(NSString *)[scriptA objectForKey:@"Title"] caseInsensitiveCompare:[scriptB objectForKey:@"Title"]];
		}
	} else {
		//Sort by title if neither is in a set; otherwise sort the one in a set to the top
		
		if (!setA && !setB) {
			result = [(NSString *)[scriptA objectForKey:@"Title"] caseInsensitiveCompare:[scriptB objectForKey:@"Title"]];
		
		} else if (!setA) {
			result = NSOrderedDescending;
		} else {
			result = NSOrderedAscending;
		}
	}
	
	return result;
}

/*!
 * @brief Sort by descending length so the longest keywords are at the beginning of the array
 */
NSInteger _scriptKeywordLengthSort(id scriptA, id scriptB, void *context)
{
	NSComparisonResult result;
	
	NSUInteger lengthA = [(NSString *)[scriptA objectForKey:@"Keyword"] length];
	NSUInteger lengthB = [(NSString *)[scriptB objectForKey:@"Keyword"] length];
	if (lengthA > lengthB) {
		result = NSOrderedAscending;
	} else if (lengthA < lengthB) {
		result = NSOrderedDescending;
	} else {
		result = NSOrderedSame;
	}
	
	return result;
}

/*!
 * @brief Append an array of scripts to a menu
 *
 * @param scripts The scripts, each of which is represented by an NSDictionary instance
 * @param menu The menu to which to add the scripts
 */
- (void)_appendScripts:(NSArray *)scripts toMenu:(NSMenu *)menu
{
	NSDictionary	*appendDict;
	NSString		*lastSet = nil;
	NSString		*set;
	NSInteger		indentationLevel;
	
	for (appendDict in scripts) {
		NSString	*title;
		NSMenuItem	*item;
		
		if ((set = [appendDict objectForKey:@"Set"])) {
			indentationLevel = 1;
			
			if (![set isEqualToString:lastSet]) {
				//We have a new set of scripts; create a section header for them
				item = [[NSMenuItem alloc] initWithTitle:set
																			 target:nil
																			 action:nil
																	  keyEquivalent:@""];
				if ([item respondsToSelector:@selector(setIndentationLevel:)]) [item setIndentationLevel:0];
				[menu addItem:item];

				lastSet = set;
			}
		} else {
			//Scripts not in sets need not be indented
			indentationLevel = 0;
			lastSet = nil;
		}
	
		if ([appendDict objectForKey:@"Title"]) {
			title = [NSString stringWithFormat:@"%@ (%@)", [appendDict objectForKey:@"Title"], [appendDict objectForKey:@"Keyword"]];
		} else {
			title = [appendDict objectForKey:@"Keyword"];
		}
		
		item = [[NSMenuItem alloc] initWithTitle:title
																	 target:self
																	 action:@selector(selectScript:)
															  keyEquivalent:@""];

		[item setRepresentedObject:appendDict];
		if ([item respondsToSelector:@selector(setIndentationLevel:)]) [item setIndentationLevel:indentationLevel];
		[menu addItem:item];
	}
}

/*!
 * @brief Insert a script's keyword into the text entry area
 *
 * This will be called by an NSMenuItem when it is clicked.
 */
- (IBAction)selectScript:(id)sender
{
	NSResponder	*responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];
	
	//Append our string into the responder if possible
	if (responder && [responder isKindOfClass:[NSTextView class]]) {
		NSArray		*arguments = [[sender representedObject] objectForKey:@"Arguments"];
		NSString	*replacementText = [[sender representedObject] objectForKey:@"Keyword"];
		
		[(NSTextView *)responder insertText:replacementText replacementRange:NSMakeRange(NSNotFound, 0)];
		
		//Append arg list to replacement string, to show the user what they can pass
		if (arguments) {
			NSDictionary		*originalTypingAttributes = [(NSTextView *)responder typingAttributes];
			NSMutableDictionary *italicizedTypingAttributes = [originalTypingAttributes mutableCopy];
			NSString			*anArgument;
			BOOL				insertedFirst = NO;
			
			[italicizedTypingAttributes setObject:[[NSFontManager sharedFontManager] convertFont:[originalTypingAttributes objectForKey:NSFontAttributeName]
																					 toHaveTrait:NSItalicFontMask]
										   forKey:NSFontAttributeName];
			
			[(NSTextView *)responder insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)];
			
			//Will that be a five minute argument or the full half hour?
			for (anArgument in arguments) {
				//Insert a comma after each argument past the first
				if (insertedFirst) {
					[(NSTextView *)responder insertText:@"," replacementRange:NSMakeRange(NSNotFound, 0)];					
				} else {
					insertedFirst = YES;
				}
				
				//Turn on the italics version, insert the argument, then go back to normal for either the comma or the ending
				[(NSTextView *)responder setTypingAttributes:italicizedTypingAttributes];
				[(NSTextView *)responder insertText:anArgument replacementRange:NSMakeRange(NSNotFound, 0)];
				[(NSTextView *)responder setTypingAttributes:originalTypingAttributes];
			}

			[(NSTextView *)responder insertText:@"}" replacementRange:NSMakeRange(NSNotFound, 0)];
		}
	}
}

/*!
 * @brief Fake target to allow validateMenuItem: to be called
 */
-(IBAction)dummyTarget:(id)sender{
}

/*!
 * @brief Validate menu item
 * Disable the insertion if a text field is not active
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ((menuItem == scriptMenuItem) || (menuItem == contextualScriptMenuItem)) {
		return YES; //Always keep the submenu enabled so users can see the available scripts
	} else {
		NSResponder	*responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];
		if (responder && [responder isKindOfClass:[NSText class]]) {
			return [(NSText *)responder isEditable];
		} else {
			return NO;
		}
	}
}

//Message Filtering ----------------------------------------------------------------------------------------------------
#pragma mark Message Filtering
/*!
 * @brief Delayed filter messages for keywords to replace
 *
 * Will eventually replace any script keywords with the result of running the script (with arguments as appropriate).
 * @result YES if we began a delayed filtration; NO if we did not
 */
- (BOOL)delayedFilterAttributedString:(NSAttributedString *)inAttributedString context:(id)context uniqueID:(unsigned long long)uniqueID
{
	BOOL		beganProcessing = NO; 
	NSString	*stringMessage;

	if ((stringMessage = [inAttributedString string])) {
		//Replace all keywords
		for (NSMutableDictionary *infoDict in flatScriptArray) {
			NSString	*keyword = [infoDict objectForKey:@"Keyword"];
			BOOL		prefixOnly = [[infoDict objectForKey:@"PrefixOnly"] boolValue];

			if ((prefixOnly && ([stringMessage rangeOfString:keyword options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location == 0)) ||
			   (!prefixOnly && [stringMessage rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound)) {
				NSMutableAttributedString	*workingCopy = [inAttributedString mutableCopy];

				/* Only claim to have begun if a script run was actually handed off. If it wasn't,
				 * we keep looking: a broken script must not hide a working one, and if none of them
				 * starts we return NO, so the caller gets its text back at once with the keyword
				 * still visible instead of waiting forever for a result nobody will deliver.
				 */
				if ([self _replaceKeyword:keyword
							   withScript:infoDict
								 inString:stringMessage
					   inAttributedString:workingCopy
								  context:context
								 uniqueID:uniqueID]) {
					NSNumber	*shouldSendNumber = [infoDict objectForKey:@"ShouldSend"];

					if ((shouldSendNumber) &&
						(![shouldSendNumber boolValue]) &&
						([context isKindOfClass:[AIContentObject class]])) {
						[(AIContentObject *)context setSendContent:NO];
					}

					beganProcessing = YES;
					break;
				}
			}
		}
	}
	
    return beganProcessing;
}

/*!
 * @brief Filter priority
 *
 * Filter earlier than the default
 */
- (CGFloat)filterPriority
{
	return HIGH_FILTER_PRIORITY;
}

/*!
 * @brief Replace one instance of a keyword within a string. This will be called once for each instance.
 *
 * @result YES if a script run was started; NO if the keyword was only found inside a link or the run could not be started
 */
- (BOOL)_replaceKeyword:(NSString *)keyword
			 withScript:(NSMutableDictionary *)infoDict
			   inString:(NSString *)inString
	 inAttributedString:(NSMutableAttributedString *)attributedString
				context:(id)context
			   uniqueID:(unsigned long long)uniqueID
{
	NSScanner	*scanner;
	BOOL		startedRun = NO;
	BOOL		foundKeyword = NO;

	//Scan for the keyword
	scanner = [NSScanner scannerWithString:inString];
	while (![scanner isAtEnd] && !foundKeyword) {
		[scanner scanUpToString:keyword intoString:nil];
		
		if (([scanner scanString:keyword intoString:nil]) &&
			([attributedString attribute:NSLinkAttributeName
								 atIndex:([scanner scanLocation]-1) /* The scanner ends up one past the keyword */
						  effectiveRange:nil] == nil)) {
			//Scan the keyword and ensure it was not found within a link
			NSInteger 		keywordStart, keywordEnd;
			NSArray 	*argArray = nil;
			NSString	*argString;
			
			//Scan arguments
			keywordStart = [scanner scanLocation] - [keyword length];
			if ([scanner scanString:@"{" intoString:nil]) {
				if ([scanner scanUpToString:@"}" intoString:&argString]) {
					argArray = [self _argumentsFromString:argString forScript:infoDict];
					[scanner scanString:@"}" intoString:nil];
				}				
			}
			keywordEnd = [scanner scanLocation];		
			
			//Run the script.
			NSRange	keywordRange = NSMakeRange(keywordStart, keywordEnd - keywordStart);
			startedRun = [self _executeScript:infoDict
								withArguments:argArray
						  forAttributedString:attributedString
								 keywordRange:keywordRange
									  context:context
									 uniqueID:uniqueID];

			/* We stop at the first occurrence either way. If the run could not be started it was
			 * the script itself which was unusable, so the next occurrence of the same keyword
			 * would fail for exactly the same reason.
			 */
			foundKeyword = YES;
		}
	}

	return startedRun;
}

/*!
 * @brief Execute the script
 *
 * When the script is complete, we will be notified, at which point we perform the replacement for the script result
 * and pass the modified attributed string back to the content controller for use.
 *
 * @result YES if the run was handed off; NO if we could not even start, in which case nobody may wait for us
 */
- (BOOL)_executeScript:(NSMutableDictionary *)infoDict
			   withArguments:(NSArray *)arguments
		 forAttributedString:(NSMutableAttributedString *)attributedString
				keywordRange:(NSRange)keywordRange
					 context:(id)context
					uniqueID:(unsigned long long)uniqueID
{
	NSString	*path = [infoDict objectForKey:@"Path"];

	/* Nothing to run means the filter must not report YES: the content controller would then wait
	 * for a completion which will never arrive, and the chat's send queue stays blocked forever.
	 */
	if (![path length]) {
		NSLog(@"GBApplescriptFiltersPlugin: no script file for keyword %@; leaving the keyword in place",
			  [infoDict objectForKey:@"Keyword"]);
		return NO;
	}

	NSDictionary	*userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
		attributedString, @"Mutable Attributed String",
		NSStringFromRange(keywordRange), @"Range",
		[NSNumber numberWithUnsignedLongLong:uniqueID], @"uniqueID",
		(context ? context : [NSNull null]), @"context",
		nil];

	//Arm the watchdog before we start, so we cannot lose the race against a very fast script
	[self _armWatchdogForUniqueID:uniqueID attributedString:attributedString];

	//Count this link of the chain; -applescriptDidRun: refuses to add another one past the ceiling
	NSNumber	*uniqueIDNumber = [NSNumber numberWithUnsignedLongLong:uniqueID];

	if (!scriptChainDepth) scriptChainDepth = [[NSMutableDictionary alloc] init];
	[scriptChainDepth setObject:[NSNumber numberWithUnsignedInteger:([[scriptChainDepth objectForKey:uniqueIDNumber] unsignedIntegerValue] + 1)]
						 forKey:uniqueIDNumber];

	[adium.applescriptabilityController runApplescriptAtPath:path
													  function:@"substitute"
													 arguments:arguments
											   notifyingTarget:self
													  selector:@selector(applescriptDidRun:resultString:)
													  userInfo:userInfo];

	return YES;
}

/*!
 * @brief Arm the watchdog for a script run
 *
 * NSAppleScript runs cannot be cancelled, so this is our only way of getting the message moving
 * again if a script never comes back.
 */
- (void)_armWatchdogForUniqueID:(unsigned long long)uniqueID
			   attributedString:(NSMutableAttributedString *)attributedString
{
	NSNumber	*uniqueIDNumber = [NSNumber numberWithUnsignedLongLong:uniqueID];

	if (!pendingScriptRuns) pendingScriptRuns = [[NSMutableDictionary alloc] init];

	//A second keyword in the same message reuses the uniqueID; the previous watchdog is done with
	[[pendingScriptRuns objectForKey:uniqueIDNumber] invalidate];

	NSTimer	*timer = [NSTimer timerWithTimeInterval:SCRIPT_TIMEOUT
											 target:self
										   selector:@selector(scriptRunTimedOut:)
										   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
													 uniqueIDNumber, @"uniqueID",
													 attributedString, @"Mutable Attributed String",
													 nil]
											repeats:NO];

	/* Common modes on purpose: in the default mode the watchdog would stay silent while a menu is
	 * open or a window is being dragged -- which is precisely when the user is still typing away.
	 */
	[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

	[pendingScriptRuns setObject:timer forKey:uniqueIDNumber];
}

/*!
 * @brief Claim the one ticket which exists for a script run
 *
 * @result YES if this caller may finish the run; NO if somebody else (the watchdog) already did
 */
- (BOOL)_consumeRunForUniqueID:(unsigned long long)uniqueID
{
	NSNumber	*uniqueIDNumber = [NSNumber numberWithUnsignedLongLong:uniqueID];
	NSTimer		*timer = [pendingScriptRuns objectForKey:uniqueIDNumber];

	if (!timer) return NO;

	[timer invalidate];
	[pendingScriptRuns removeObjectForKey:uniqueIDNumber];

	return YES;
}

/*!
 * @brief Drop everything we were keeping for a filtration which is over
 */
- (void)_forgetFiltration:(unsigned long long)uniqueID
{
	[scriptChainDepth removeObjectForKey:[NSNumber numberWithUnsignedLongLong:uniqueID]];
}

/*!
 * @brief The content filter framework gave up on one of our filtrations
 *
 * Let go of the watchdog we still have armed for it. Beyond saving the message copy and the content
 * object from being held for another half minute, this closes the ticket: the framework has already
 * passed our working copy on to be sent, and a script result arriving afterwards must not be allowed
 * to edit a string which is on its way out.
 */
- (void)delayedFilterWasCancelledForUniqueID:(unsigned long long)uniqueID
{
	[self _consumeRunForUniqueID:uniqueID];
	[self _forgetFiltration:uniqueID];
}

/*!
 * @brief A script took too long
 *
 * Finish the delayed filtration with what we have. The keyword is still standing in that string,
 * which is exactly what the user should see: better a message with a visible /chuck in it than a
 * message which never leaves and a chat which never accepts another one.
 */
- (void)scriptRunTimedOut:(NSTimer *)timer
{
	NSDictionary				*timerInfo = [timer userInfo];
	NSNumber					*uniqueIDNumber = [timerInfo objectForKey:@"uniqueID"];
	NSMutableAttributedString	*attributedString = [timerInfo objectForKey:@"Mutable Attributed String"];

	[pendingScriptRuns removeObjectForKey:uniqueIDNumber];
	[self _forgetFiltration:[uniqueIDNumber unsignedLongLongValue]];

	NSLog(@"GBApplescriptFiltersPlugin: a script did not finish within %i seconds; sending the message with the keyword unreplaced (filter %@)",
		  SCRIPT_TIMEOUT, uniqueIDNumber);

	/* Out of the timer callout first. This watchdog runs in the common modes on purpose -- otherwise
	 * it would stay quiet for as long as a menu is open, which is exactly when the user notices that
	 * nothing is going out -- but finishing the filtration means running the entire send pipeline,
	 * and that should not happen on top of a CFRunLoopTimer callout. The ticket above is already
	 * gone, so a script result arriving in the meantime is refused as usual.
	 */
	dispatch_async(dispatch_get_main_queue(), ^{
		[adium.contentController delayedFilterDidFinish:attributedString
											   uniqueID:[uniqueIDNumber unsignedLongLongValue]];
	});
}

/*!
 * @brief A script finished running
 */
- (void)applescriptDidRun:(id)userInfo resultString:(NSString *)resultString
{
	NSMutableAttributedString	*attributedString = [userInfo objectForKey:@"Mutable Attributed String"];
	NSRange						keywordRange = NSRangeFromString([userInfo objectForKey:@"Range"]);
	unsigned long long			uniqueID = [[userInfo objectForKey:@"uniqueID"] unsignedLongLongValue];

	//The watchdog may have finished this filtration already; a late result is dropped rather than finishing it twice
	if (![self _consumeRunForUniqueID:uniqueID]) return;

	BOOL	didReplace = NO;

	/* A nil result means the script gave us nothing -- missing handler, compile error, runtime
	 * error. We leave the keyword alone in that case; sending "/chuck" is annoying, silently eating
	 * what the user typed is worse. A script which deliberately returns an empty string hands us
	 * @"" rather than nil and still replaces the keyword with nothing.
	 */
	if (resultString) {
		//Replace the substring with script result
		if (NSMaxRange(keywordRange) <= [attributedString length]) {
			if (([resultString hasPrefix:@"<HTML>"])) {
				//Obtain the attributed string version of the HTML, passing our current attributes as the default ones
				NSAttributedString *attributedScriptResult = [AIHTMLDecoder decodeHTML:resultString
																 withDefaultAttributes:[attributedString attributesAtIndex:keywordRange.location
																											effectiveRange:nil]];
				[attributedString replaceCharactersInRange:keywordRange
									  withAttributedString:attributedScriptResult];

			} else {
				[attributedString replaceCharactersInRange:keywordRange
												withString:resultString];
			}

			didReplace = YES;
		}
	}

	/* Only look for further keywords if this one is actually gone. If it is still standing -- the
	 * script failed -- another pass would find it again, start the very same script again and fail
	 * in the very same way, forever. We finish here instead, and any second keyword in the message
	 * simply stays unsubstituted as well.
	 *
	 * A replacement is not proof of progress either: a script which answers "%_uptime unavailable"
	 * puts its own keyword back into the string, and the next pass searches the whole string again
	 * and finds it. That loop replaces text every time, so the test above would never catch it --
	 * hence the ceiling on how many times one message may send us round.
	 */
	NSUInteger	chainDepth = [[scriptChainDepth objectForKey:[NSNumber numberWithUnsignedLongLong:uniqueID]] unsignedIntegerValue];

	if (didReplace && (chainDepth >= SCRIPT_CHAIN_LIMIT)) {
		NSLog(@"GBApplescriptFiltersPlugin: filtration %llu ran %lu scripts without settling; a script is probably reproducing its own keyword. Sending what we have",
			  uniqueID, (unsigned long)chainDepth);

	} else if (didReplace &&
			   [self delayedFilterAttributedString:attributedString
										   context:[userInfo objectForKey:@"context"]
										  uniqueID:uniqueID]) {
		/* Another script is running now, so we are not finished -- but this much is done and must not
		 * be thrown away. Reporting it hands the framework the current text as its fallback and
		 * restarts its deadline for this link, so its patience is measured per script, the way ours
		 * is. Without it the whole chain shares one deadline and an overrun sends out the message
		 * exactly as the user typed it, discarding every substitution already made.
		 */
		[adium.contentController delayedFilterDidProgress:attributedString
												 uniqueID:uniqueID];
		return;
	}

	//Inform the content controller that we're done
	[self _forgetFiltration:uniqueID];
	[adium.contentController delayedFilterDidFinish:attributedString
										   uniqueID:uniqueID];
}

/*!
 * @brief Determine the arguments for a script execution
 *
 * @param inString The string of potential arguments
 * @param scriptDict The script being executed
 *
 * @result An NSArray of NSString instances
 */
- (NSArray *)_argumentsFromString:(NSString *)inString forScript:(NSMutableDictionary *)scriptDict
{
	NSArray			*scriptArguments = [scriptDict objectForKey:@"Arguments"];
	NSMutableArray	*argArray = [NSMutableArray array];
	NSArray			*inStringComponents = [inString componentsSeparatedByString:@","];
	
	NSUInteger		i = 0;
	NSUInteger		count = (scriptArguments ? [scriptArguments count] : 0);
	NSUInteger		inStringComponentsCount = [inStringComponents count];
	
	//Add each argument of inString to argArray so long as the number of arguments is less
	//than the number of expected arguments for the script and the number of supplied arguments
	while ((i < count) && (i < inStringComponentsCount)) {
		[argArray addObject:[inStringComponents objectAtIndex:i]];
		i++;
	}
	
	//If more components were passed than were actually requested, the last argument gets the
	//remainder
	if (i < inStringComponentsCount) {
		NSRange	remainingRange;
		
		//i was incremented to end the while loop if i > 0, so subtract 1 to reexamine the last object
		remainingRange.location = ((i > 0) ? i-1 : 0);
		remainingRange.length = (inStringComponentsCount - remainingRange.location);

		if (remainingRange.location != NSNotFound) {
			NSString	*lastArgument;

			//Remove that last, incomplete argument if it was added
			if ([argArray count]) [argArray removeLastObject];

			//Create the last argument by joining all remaining comma-separated arguments with a comma
			lastArgument = [[inStringComponents subarrayWithRange:remainingRange] componentsJoinedByString:@","];

			[argArray addObject:lastArgument];
		}
	}
	
	return argArray;
}

#pragma mark Toolbar item
/*!
 * @brief Register our insert script toolbar item
 */
- (void)registerToolbarItem
{
	MVMenuButton *button;
	
	//Unregister the existing toolbar item first
	if (toolbarItem) {
		[adium.toolbarController unregisterToolbarItem:toolbarItem forToolbarType:@"TextEntry"];
		toolbarItem = nil;
	}

	//Register our toolbar item
	button = [[MVMenuButton alloc] initWithFrame:NSMakeRect(0,0,32,32)];
	[button setImage:[NSImage imageNamed:@"msg-insert-script" forClass:[self class] loadLazily:YES]];
	toolbarItem = [AIToolbarUtilities toolbarItemWithIdentifier:SCRIPT_IDENTIFIER
														   label:AILocalizedString(@"Scripts",nil)
													paletteLabel:TITLE_INSERT_SCRIPT
														 toolTip:AILocalizedString(@"Insert a script",nil)
														  target:self
												 settingSelector:@selector(setView:)
													 itemContent:button
														  action:@selector(selectScript:)
															menu:nil];
	[toolbarItem setMinSize:NSMakeSize(32,32)];
	[toolbarItem setMaxSize:NSMakeSize(32,32)];
	[button setToolbarItem:toolbarItem];
    [adium.toolbarController registerToolbarItem:toolbarItem forToolbarType:@"TextEntry"];
}

/*!
 * @brief After the toolbar has added the item we can set up the submenus
 */
- (void)toolbarWillAddItem:(NSNotification *)notification
{
	NSToolbarItem	*item = [[notification userInfo] objectForKey:@"item"];
	
	if (!notification || ([[item itemIdentifier] isEqualToString:SCRIPT_IDENTIFIER])) {
		NSMenu		*menu = [[scriptMenuItem submenu] copy];

		//Add menu to view
		[[item view] setMenu:menu];

		//Add menu to toolbar item (for text mode)
		NSMenuItem	*mItem = [[NSMenuItem alloc] init];
		[mItem setSubmenu:menu];
		[mItem setTitle:[menu title]];
		[item setMenuFormRepresentation:mItem];
	}
}

@end
