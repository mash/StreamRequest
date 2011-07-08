#import "StreamRequest.h"
#import "NSString+SBJSON.h"

#define STREAM_REQUEST_TIMEOUT (60.*60.*24.) // 24hours

@implementation StreamRequest
@synthesize delegate = _delegate, url = _url, request = _request, connection = _connection, boundary = _boundary, leftover = _leftover, errorBody = _errorBody;
@synthesize statusCode;

- (void) dealloc {
    [ self cancel ];
    self.delegate = nil;
    [ self.request release ];
    [ self.url release ];
    [ self.connection release ];
    [ self.boundary release ];
    [ self.leftover release ];
    [ self.errorBody release ];
    [super dealloc];
}

- (id) initWithURL: (NSString*)url_ delegate: (id<StreamRequestDelegate>) delegate_ {
    if ( (self = [super init]) == nil ) {
        return nil;
    }

    self.url      = url_;
    self.delegate = delegate_;
    self.request  = nil;

    return self;
}

- (void) start {
    if ( ! self.request ) {
        self.boundary = nil;
        self.leftover = nil;
        self.statusCode = 0;
        self.errorBody = nil;

        self.request = [ NSURLRequest requestWithURL: [ NSURL URLWithString: self.url ]
                                         cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval: STREAM_REQUEST_TIMEOUT ];
        NSURLConnection* conn= [NSURLConnection connectionWithRequest: self.request delegate: self ];
        self.connection = conn;

        if ( [ self.delegate respondsToSelector: @selector(requestDidStartLoad:) ] ) {
            [ self.delegate performSelector: @selector(requestDidStartLoad:)
                                 withObject: self ];
        }

    }
}

- (void) restart {
    [ self cancel ];
    [ self start ];
}

- (void) cancel {
    if ( self.request ) {
        [ self.connection cancel ];
        self.request = nil;
        self.connection = nil;
    }
}

- (BOOL) isActive {
    return self.request ? YES : NO;
}

- (NSString*) parseBoundaryFromHeaders: (NSDictionary*) allHeaders {
    NSString* contentType = [allHeaders objectForKey: @"Content-Type"];
    if ( ! contentType ) {
        // case-insensitive
        contentType = [allHeaders objectForKey: @"content-type"];
    }
    if ( ! contentType ) {
        // otherwise abort
        return nil;
    }

    // http://www.w3.org/Protocols/rfc1341/7_2_Multipart.html
    NSString* pattern = @"boundary=\"?([0-9a-z'\\(\\)\\+\\_\\,\\-\\.\\/\\:\\=\\?\\ ]+)\"?";
    NSRegularExpression *regex = [NSRegularExpression
                                     regularExpressionWithPattern: pattern
                                                          options: NSRegularExpressionCaseInsensitive
                                                            error: NULL ];
    NSTextCheckingResult* result = [ regex firstMatchInString: contentType
                                                      options: 0
                                                        range: NSMakeRange(0, [contentType length]) ];
    if ( result && ([result numberOfRanges]>=2) ) {
        NSRange firstMatch = [result rangeAtIndex:1];
        NSString* substringForFirstMatch = [contentType substringWithRange: firstMatch ];
        return substringForFirstMatch;
    }
    return nil;
}

- (void) divideWithBoundaryAndDispatchEvents {
    // http://www.w3.org/Protocols/rfc1341/7_2_Multipart.html
    // CRLF looks like only LF here?
    while ( YES ) {
        NSRange range = [ self.leftover rangeOfString: [NSString stringWithFormat: @"--%@\n", self.boundary] ];
        if ( NSEqualRanges( range, NSMakeRange(NSNotFound, 0) ) ) {
            break;
        }
        if ( range.location == 0 ) {
            // parse content following the boundary
            range = NSMakeRange( range.location + range.length,
                                 [self.leftover length] - range.length );
        }
        else {
            // found one part
            range = NSMakeRange( 0, range.location );
            NSString* part = [ self.leftover substringWithRange: range ];
            [ self notifyReceivedData: part ];

            range = NSMakeRange( range.location + range.length,
                                 [self.leftover length] - range.location - range.length );
        }
        self.leftover = [ self.leftover substringWithRange: range ];
    }
}

- (void) notifyReceivedData: (NSString*) string {
    NSRange range = [string rangeOfString: @"Content-Type: application/json"
                                  options: NSCaseInsensitiveSearch];
    if ( NSEqualRanges( range, NSMakeRange(NSNotFound, 0) ) ) {
        // non application/json responses are text/html , bring text
        // 1: \n
        string = [ string substringWithRange: NSMakeRange( 1, [string length]-1 ) ];
        if ( [ self.delegate respondsToSelector: @selector(request:didReceiveString:) ] ) {
            [ self.delegate performSelector: @selector(request:didReceiveString:)
                                 withObject: self
                                 withObject: string ];
        }
    }
    else {
        // 1: \n
        range.location = range.location + range.length + 1;
        range.length   = [string length] - range.location;
        if ( [ self.delegate respondsToSelector: @selector(request:didReceiveJSON:) ] ) {
            string = [ string substringWithRange: range ];
            NSDictionary* dic = [ string JSONValue ];
            [ self.delegate performSelector: @selector(request:didReceiveJSON:)
                                 withObject: self
                                 withObject: dic ];
        }
    }
}

#pragma mark -
#pragma mark NSURLConnection delegates

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [ self.delegate request: self
       didFailLoadWithError: error ];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ( [ self.delegate respondsToSelector: @selector(request:didReceiveAuthenticationChallenge:) ] ) {
        [ self.delegate performSelector: @selector(request:didReceiveAuthenticationChallenge:)
                             withObject: self
                             withObject: challenge ];
        return;
    }

    [ challenge.sender continueWithoutCredentialForAuthenticationChallenge: challenge ];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    NSString* content = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];

    if ( ! content ) {
        return;
    }

    if ( self.statusCode == 200 ) {
        if ( self.boundary ) {
            if ( self.leftover ) {
                self.leftover = [ self.leftover stringByAppendingString: content ];
            }
            else {
                self.leftover = content;
            }
            [ self divideWithBoundaryAndDispatchEvents ];
        }
    }
    else {
        if ( self.errorBody ) {
            self.errorBody = [ self.errorBody stringByAppendingString: content ];
        }
        else {
            self.errorBody = content;
        }
    }

    [ content release ];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response_ {
    NSHTTPURLResponse* response = (NSHTTPURLResponse*) response_;
    self.statusCode = [ response statusCode ];
    if ( self.statusCode == 200 ) {
        NSString* boundary = [ self parseBoundaryFromHeaders: [response allHeaderFields] ];
        self.boundary = boundary;
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if ( self.statusCode == 200 ) {
        if ( [ self.delegate respondsToSelector: @selector(requestDidFinishLoad:) ] ) {
            [ self.delegate performSelector: @selector(requestDidFinishLoad:)
                                 withObject: self ];
        }
    }
    else {
        if ( [ self.delegate respondsToSelector: @selector(request:didFailLoadWithError:) ] ) {
            [ self.delegate performSelector: @selector(request:didFailLoadWithError:)
                                 withObject: self
                                 withObject: nil ];
        }
    }
}

@end
