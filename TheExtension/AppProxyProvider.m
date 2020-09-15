#import "AppProxyProvider.h"

API_AVAILABLE(macos(10.15.4))
@implementation AppProxyProvider {
    dispatch_queue_t _queue;
}

- (NENetworkRule *)ruleWithHost:(NSString *)host prefixLen:(NSUInteger)prefix port:(NSUInteger)port proto:(NENetworkRuleProtocol)proto {
    return [[NENetworkRule alloc] initWithRemoteNetwork:[NWHostEndpoint endpointWithHostname:host port:@(port).stringValue]
                                           remotePrefix:prefix
                                           localNetwork:nil
                                            localPrefix:0
                                               protocol:proto
                                              direction:NETrafficDirectionOutbound];
}

- (void)startProxyWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler {
    NETransparentProxyNetworkSettings *settings =
            [[NETransparentProxyNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];
    
    // 0.0.0.0/0 - 224.0.0.0/3 - 0.0.0.0/8
    settings.includedNetworkRules = @[
        [self ruleWithHost:@"1.0.0.0"   prefixLen:8 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"2.0.0.0"   prefixLen:7 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"4.0.0.0"   prefixLen:6 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"8.0.0.0"   prefixLen:5 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"16.0.0.0"  prefixLen:4 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"32.0.0.0"  prefixLen:3 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"64.0.0.0"  prefixLen:2 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"128.0.0.0" prefixLen:2 port:0 proto:NENetworkRuleProtocolTCP],
        [self ruleWithHost:@"192.0.0.0" prefixLen:3 port:0 proto:NENetworkRuleProtocolTCP],
    ];
    
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"setTunnelNetworkSettings: %@", error.localizedDescription);
        }
    }];
    
    _queue = dispatch_queue_create(nil, nil);
    
    if (completionHandler != nil) {
        completionHandler(nil);
    }
}

- (void)stopProxyWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    if (completionHandler != nil) {
        completionHandler();
    }
}

- (void)handleAppMessage:(NSData *)messageData completionHandler:(void (^)(NSData *))completionHandler {
    if (completionHandler != nil) {
        completionHandler(messageData);
    }
}

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    if (completionHandler != nil) {
        completionHandler();
    }
}

- (void)wake {
    // Add code here to wake up.
}

static void incoming(nw_connection_t conn, NEAppProxyTCPFlow *flow) API_AVAILABLE(macos(10.15.4)) {
    nw_connection_receive(conn, 0, 64 * 1024, ^(dispatch_data_t  _Nullable content,
                                                nw_content_context_t  _Nullable context,
                                                bool is_complete,
                                                nw_error_t  _Nullable error) {
        if (error) {
            if (ECANCELED == nw_error_get_error_code(error)) {
                return;
            }
            NSError *nserror = (__bridge_transfer NSError *) nw_error_copy_cf_error(error);
            NSLog(@"nw_connection_receive: %@", nserror.localizedDescription);
            nw_connection_force_cancel(conn);
            [flow closeReadWithError:nil];
            [flow closeWriteWithError:nil];
            return;
        }
        
        if (is_complete && content == nil) {
            NSLog(@"Got EOF from socket, closing write, flow: %@", flow);
            [flow closeWriteWithError:nil];
            return;
        }
        
        dispatch_data_apply(content, ^bool(dispatch_data_t  _Nonnull region, size_t offset,
                                           const void * _Nonnull buffer, size_t size) {
            BOOL last = (offset + size) == dispatch_data_get_size(content);
            BOOL complete = is_complete && last;
            [flow writeData:[NSData dataWithBytes:buffer length:size] withCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"writeData: %@", error.localizedDescription);
                    nw_connection_force_cancel(conn);
                    [flow closeReadWithError:nil];
                    [flow closeWriteWithError:nil];
                    return;
                }
                if (complete) {
                    NSLog(@"Got EOF from socket, closing write, flow: %@", flow);
                    [flow closeWriteWithError:nil];
                    return;
                }
                if (last) {
                    incoming(conn, flow);
                }
            }];
            return YES;
        });
    });
}

static void outgoing(NEAppProxyTCPFlow *flow, nw_connection_t conn, dispatch_queue_t queue) API_AVAILABLE(macos(10.15.4)) {
    [flow readDataWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            NSLog(@"readDataWithCompletionHandler: %@", error.localizedDescription);
            nw_connection_force_cancel(conn);
            [flow closeReadWithError:nil];
            [flow closeWriteWithError:nil];
            return;
        }
        
        BOOL complete = (data.length == 0);
        
        if (complete) {
            NSLog(@"Got EOF from flow, closing read, flow: %@", flow);
            [flow closeReadWithError:nil];
        }
        
        dispatch_data_t ddata = dispatch_data_create(data.bytes, data.length, nil, ^{
            [data length]; // Capture and retain
        });
        
        dispatch_async(queue, ^{
            nw_connection_send(conn, ddata, NW_CONNECTION_DEFAULT_STREAM_CONTEXT, complete, ^(nw_error_t  _Nullable error) {
                if (error) {
                    if (ECANCELED == nw_error_get_error_code(error)) {
                        return;
                    }
                    NSError *nserror = (__bridge_transfer NSError *) nw_error_copy_cf_error(error);
                    NSLog(@"nw_connection_send: %@", nserror.localizedDescription);
                    nw_connection_force_cancel(conn);
                    [flow closeReadWithError:nil];
                    [flow closeWriteWithError:nil];
                    return;
                }
                if (!complete) {
                    outgoing(flow, conn, queue);
                }
            });
        });
    }];
}

- (BOOL)handleNewFlow:(NEAppProxyFlow *)flow {
    NEAppProxyTCPFlow *tcpFlow = (NEAppProxyTCPFlow *) flow;
    dispatch_queue_t queue = _queue;
    [flow openWithLocalEndpoint:nil completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"openWithLocalEndpoint: %@", error.localizedDescription);
            return;
        }
        
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                                     NW_PARAMETERS_DEFAULT_CONFIGURATION);
        [flow setMetadata:parameters];
        
        NWHostEndpoint *hostEndpoint = (NWHostEndpoint *) tcpFlow.remoteEndpoint;
        nw_endpoint_t endpoint = nw_endpoint_create_host(hostEndpoint.hostname.UTF8String,
                                                         hostEndpoint.port.UTF8String);
        
        nw_connection_t conn = nw_connection_create(endpoint, parameters);
        nw_connection_set_queue(conn, queue);
        nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t  _Nullable error) {
            if (error) {
                NSError *nserror = (__bridge_transfer NSError *) nw_error_copy_cf_error(error);
                NSLog(@"nw_connection_set_state_changed_handler: %@", nserror.localizedDescription);
            }
            NSLog(@"Conn: %p state: %d", (__bridge void *) conn, state);
            if (state == nw_connection_state_ready) {
                incoming(conn, tcpFlow);
                outgoing(tcpFlow, conn, queue);
            }
        });
        nw_connection_start(conn);
    }];
    return YES;
}

@end
