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

#import <Foundation/Foundation.h>

/*! @brief One thing a call needs, and whether this machine grants it */
@interface AIJingleCallFinding : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic) BOOL good;
@property (nonatomic) BOOL fatal;			//a call cannot work while this is wrong
@property (nonatomic, copy) NSString *settingsURL;	//where the person can change it, or nil
@end

/*!
 * @class AIJingleCallDiagnostics
 * @brief What a call needs from this machine, asked one question at a time
 *
 * macOS decides per application whether it may use the microphone, the camera
 * and the network around it, and a refusal is silent: calls simply stop working,
 * often long after the answer was given. These checks ask each question out
 * loud, and the ones that can be measured are measured rather than assumed: the
 * network questions are answered by really talking, once to the world through a
 * STUN server and once to the neighbours through Bonjour. Asking also makes
 * macOS put its question, which is how a permission nobody was ever asked for
 * gets asked for.
 */
@interface AIJingleCallDiagnostics : NSObject

/*! @brief Run every check; the answer arrives on the main queue */
+ (void)runWithCompletion:(void (^)(NSArray<AIJingleCallFinding *> *findings))completion;

/*! @brief One line naming what is wrong, or nil when nothing is */
+ (NSString *)summaryOfFindings:(NSArray<AIJingleCallFinding *> *)findings;

@end
