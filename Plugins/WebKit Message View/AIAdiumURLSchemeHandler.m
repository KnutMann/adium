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

#import "AIAdiumURLSchemeHandler.h"

@implementation AIAdiumURLSchemeHandler

/// Returns an empty 200 response for every adium:// request.
///
/// The adium:// scheme is used only as a base URL for loadHTMLString:baseURL: to
/// namespace LocalStorage per message style. No actual resources are served through
/// this scheme — matching the behavior of the legacy AIAdiumURLProtocol NSURLProtocol
/// which it replaces.
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
	NSDictionary *headerFields = @{@"Content-Type" : @"text/plain"};

	NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[[urlSchemeTask request] URL]
															  statusCode:200
															 HTTPVersion:@"HTTP/1.1"
															headerFields:headerFields];

	[urlSchemeTask didReceiveResponse:response];
	[urlSchemeTask didReceiveData:[NSData data]];
	[urlSchemeTask didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{}

@end
