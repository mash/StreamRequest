#import <Foundation/Foundation.h>

@class StreamRequest;

@protocol StreamRequestDelegate<NSObject>

- (void) requestDidStartLoad: (StreamRequest*) request;
- (void) request: (StreamRequest*) request didReceiveString: (NSString*) string;
- (void) request: (StreamRequest*) request didReceiveJSON: (NSDictionary*) dic;
- (void) requestDidFinishLoad: (StreamRequest*) request;
- (void) request: (StreamRequest*)request didFailLoadWithError: (NSError*)error;
- (void) request: (StreamRequest*)req didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge *) challenge;

@end

@interface StreamRequest : NSObject {
    id<StreamRequestDelegate> _delegate;
    NSString*                 _url;
    NSURLRequest*             _request;
    NSURLConnection*          _connection;

    NSString*                 _boundary;
    NSString*                 _leftover;
    int                       statusCode;
    NSString*                 _errorBody;
}

@property (nonatomic, assign) id<StreamRequestDelegate> delegate;
@property (nonatomic, retain) NSString* url;
@property (nonatomic, retain) NSURLRequest* request;
@property (nonatomic, retain) NSURLConnection* connection;

@property (nonatomic, retain) NSString* boundary;
@property (nonatomic, retain) NSString* leftover;
@property (nonatomic) int statusCode;
@property (nonatomic, retain) NSString* errorBody;

- (id) initWithURL:(NSString*)URL delegate:(id<StreamRequestDelegate>)delegate;
- (void) start;
- (void) restart;
- (void) cancel;
- (BOOL) isActive;
- (NSString*) parseBoundaryFromHeaders: (NSDictionary*) allHeaders;
- (void) divideWithBoundaryAndDispatchEvents;
- (void) notifyReceivedData: (NSString*) string;

@end
