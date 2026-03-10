#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

#include <dispatch/dispatch.h>
#include <netdb.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <uuid/uuid.h>

static const uint16_t kL2CAPUUID = 0x0100;
static const uint16_t kRFCOMMUUID = 0x0003;
static const uint16_t kSerialPortUUID = 0x1101;
static const uint16_t kPublicBrowseGroupUUID = 0x1002;
static NSString * const kDefaultServiceName = @"MyNumber Bridge";
static NSString * const kBridgeServiceUUID = @"4D79534E-5244-4252-4944-474530303031";
static volatile sig_atomic_t gKeepRunning = 1;

static NSData *UInt16Data(uint16_t value) {
    uint16_t networkValue = CFSwapInt16HostToBig(value);
    return [NSData dataWithBytes:&networkValue length:sizeof(networkValue)];
}

static NSDictionary *UInt8Element(uint8_t value) {
    return @{
        @"DataElementType": @1,
        @"DataElementSize": @1,
        @"DataElementValue": @(value),
    };
}

static NSData *UUID128Data(NSString *uuidString) {
    uuid_t bytes;
    if (uuid_parse(uuidString.UTF8String, bytes) != 0) {
        return nil;
    }
    return [NSData dataWithBytes:bytes length:sizeof(uuid_t)];
}

static NSString *NormalizeBluetoothAddress(NSString *address) {
    return [[address uppercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@":"];
}

@interface RFCOMMVPCDBridge : NSObject <IOBluetoothRFCOMMChannelDelegate>

@property(nonatomic, copy) NSString *tcpHost;
@property(nonatomic) uint16_t tcpPort;
@property(nonatomic) uint8_t preferredChannel;
@property(nonatomic, copy) NSString *serviceName;
@property(nonatomic, retain) IOBluetoothSDPServiceRecord *serviceRecord;
@property(nonatomic, retain) IOBluetoothUserNotification *openNotification;
@property(nonatomic, retain) IOBluetoothRFCOMMChannel *channel;
@property(nonatomic) int tcpSocket;
@property(nonatomic) dispatch_source_t tcpReadSource;
@property(nonatomic) dispatch_queue_t ioQueue;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port channel:(uint8_t)channel serviceName:(NSString *)serviceName;
- (BOOL)start:(NSError **)error;
- (void)stop;

@end

@implementation RFCOMMVPCDBridge

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port channel:(uint8_t)channel serviceName:(NSString *)serviceName {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _tcpHost = [host copy];
    _tcpPort = port;
    _preferredChannel = channel;
    _serviceName = [serviceName copy];
    _tcpSocket = -1;
    _ioQueue = dispatch_queue_create("jp.mojashi.mynumber-bridge.rfcomm", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)start:(NSError **)error {
    IOBluetoothHostController *controller = [IOBluetoothHostController defaultController];
    if (controller == nil || controller.powerState == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:ENODEV
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bluetooth controller is unavailable or powered off."}];
        }
        return NO;
    }

    NSDictionary *serviceDictionary = [self serviceDictionary];
    self.serviceRecord = [IOBluetoothSDPServiceRecord publishedServiceRecordWithDictionary:serviceDictionary];
    if (self.serviceRecord == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EIO
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to publish RFCOMM service record."}];
        }
        return NO;
    }

    BluetoothRFCOMMChannelID channelID = 0;
    IOReturn status = [self.serviceRecord getRFCOMMChannelID:&channelID];
    if (status != kIOReturnSuccess || channelID == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EIO
                                     userInfo:@{NSLocalizedDescriptionKey: @"Published service record does not expose an RFCOMM channel."}];
        }
        return NO;
    }

    self.openNotification = [IOBluetoothRFCOMMChannel registerForChannelOpenNotifications:self
                                                                                  selector:@selector(channelOpened:channel:)
                                                                             withChannelID:channelID
                                                                                 direction:kIOBluetoothUserNotificationChannelDirectionIncoming];
    if (self.openNotification == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EIO
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to register RFCOMM open notifications."}];
        }
        return NO;
    }

    NSString *address = NormalizeBluetoothAddress(controller.addressAsString);
    NSLog(@"Published Bluetooth SPP service \"%@\"", self.serviceName);
    NSLog(@"Bluetooth address: %@", address);
    NSLog(@"RFCOMM channel: %u", channelID);
    NSLog(@"Service UUID: %@", kBridgeServiceUUID);
    NSLog(@"Android config URI: vpcd://bluetooth?address=%@", address);
    NSLog(@"Forward target: %@:%u", self.tcpHost, self.tcpPort);
    return YES;
}

- (void)stop {
    [self closeActiveBridge];
    if (self.openNotification != nil) {
        [self.openNotification unregister];
        self.openNotification = nil;
    }
    if (self.serviceRecord != nil) {
        [self.serviceRecord removeServiceRecord];
        self.serviceRecord = nil;
    }
}

- (NSDictionary *)serviceDictionary {
    NSData *customServiceUUID = UUID128Data(kBridgeServiceUUID);
    return @{
        @"0001 - ServiceClassIDList": @[
            customServiceUUID,
            UInt16Data(kSerialPortUUID),
        ],
        @"0004 - ProtocolDescriptorList": @[
            @[
                UInt16Data(kL2CAPUUID),
            ],
            @[
                UInt16Data(kRFCOMMUUID),
                UInt8Element(self.preferredChannel),
            ],
        ],
        @"0005 - BrowseGroupList*": @[
            UInt16Data(kPublicBrowseGroupUUID),
        ],
        @"0100 - ServiceName*": self.serviceName,
        @"LocalAttributes": @{
            @"Persistent": @NO,
            @"UniqueClientPerService": @YES,
        },
    };
}

- (void)channelOpened:(IOBluetoothUserNotification *)notification channel:(IOBluetoothRFCOMMChannel *)newChannel {
    (void)notification;
    if (self.channel != nil) {
        NSLog(@"Rejecting RFCOMM connection from %@ because another bridge is active.", newChannel.getDevice.nameOrAddress);
        [newChannel closeChannel];
        return;
    }

    NSError *error = nil;
    int socketFD = [self connectTCP:&error];
    if (socketFD < 0) {
        NSLog(@"Failed to connect to VPCD on %@:%u: %@", self.tcpHost, self.tcpPort, error.localizedDescription);
        [newChannel closeChannel];
        return;
    }

    self.channel = newChannel;
    [self.channel setDelegate:self];
    self.tcpSocket = socketFD;
    [self startTCPPump];
    NSLog(@"Bluetooth client connected: %@", newChannel.getDevice.nameOrAddress);
}

- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength {
    (void)rfcommChannel;
    if (self.tcpSocket < 0 || dataLength == 0) {
        return;
    }

    const uint8_t *buffer = dataPointer;
    ssize_t totalSent = 0;
    while (totalSent < (ssize_t)dataLength) {
        ssize_t sent = send(self.tcpSocket, buffer + totalSent, dataLength - totalSent, 0);
        if (sent <= 0) {
            NSLog(@"TCP write failed, closing active bridge.");
            [self closeActiveBridge];
            return;
        }
        totalSent += sent;
    }
}

- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)rfcommChannel {
    NSLog(@"Bluetooth client disconnected: %@", rfcommChannel.getDevice.nameOrAddress);
    [self closeActiveBridge];
}

- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)rfcommChannel status:(IOReturn)error {
    if (error != kIOReturnSuccess) {
        NSLog(@"RFCOMM open failed for %@: 0x%08x", rfcommChannel.getDevice.nameOrAddress, error);
        [self closeActiveBridge];
    }
}

- (int)connectTCP:(NSError **)error {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    char portString[16];
    snprintf(portString, sizeof(portString), "%u", self.tcpPort);

    struct addrinfo *result = NULL;
    int status = getaddrinfo(self.tcpHost.UTF8String, portString, &hints, &result);
    if (status != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:gai_strerror(status)]}];
        }
        return -1;
    }

    int socketFD = -1;
    for (struct addrinfo *entry = result; entry != NULL; entry = entry->ai_next) {
        socketFD = socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol);
        if (socketFD < 0) {
            continue;
        }
        if (connect(socketFD, entry->ai_addr, entry->ai_addrlen) == 0) {
            break;
        }
        close(socketFD);
        socketFD = -1;
    }
    freeaddrinfo(result);

    if (socketFD < 0 && error != NULL) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:ECONNREFUSED
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unable to connect to the local VPCD listener."}];
    }
    return socketFD;
}

- (void)startTCPPump {
    if (self.tcpSocket < 0) {
        return;
    }

    self.tcpReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.tcpSocket, 0, self.ioQueue);
    __weak RFCOMMVPCDBridge *weakSelf = self;
    dispatch_source_set_event_handler(self.tcpReadSource, ^{
        RFCOMMVPCDBridge *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.tcpSocket < 0 || strongSelf.channel == nil) {
            return;
        }

        uint8_t buffer[4096];
        ssize_t received = recv(strongSelf.tcpSocket, buffer, sizeof(buffer), 0);
        if (received <= 0) {
            NSLog(@"TCP listener closed, shutting down active bridge.");
            [strongSelf closeActiveBridge];
            return;
        }

        [strongSelf writeRFCOMMData:[NSData dataWithBytes:buffer length:(NSUInteger)received]];
    });
    dispatch_source_set_cancel_handler(self.tcpReadSource, ^{
    });
    dispatch_resume(self.tcpReadSource);
}

- (void)writeRFCOMMData:(NSData *)data {
    if (self.channel == nil || data.length == 0) {
        return;
    }

    BluetoothRFCOMMMTU mtu = [self.channel getMTU];
    if (mtu == 0) {
        mtu = 1024;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        UInt16 chunkLength = (UInt16)MIN((NSUInteger)mtu, data.length - offset);
        IOReturn status = [self.channel writeSync:(void *)(bytes + offset) length:chunkLength];
        if (status != kIOReturnSuccess) {
            NSLog(@"RFCOMM write failed: 0x%08x", status);
            [self closeActiveBridge];
            return;
        }
        offset += chunkLength;
    }
}

- (void)closeActiveBridge {
    if (self.tcpReadSource != nil) {
        dispatch_source_cancel(self.tcpReadSource);
        self.tcpReadSource = nil;
    }

    if (self.tcpSocket >= 0) {
        shutdown(self.tcpSocket, SHUT_RDWR);
        close(self.tcpSocket);
        self.tcpSocket = -1;
    }

    if (self.channel != nil) {
        IOBluetoothRFCOMMChannel *activeChannel = self.channel;
        self.channel = nil;
        [activeChannel setDelegate:nil];
        [activeChannel closeChannel];
    }
}

@end

static void PrintUsage(const char *programName) {
    fprintf(stderr, "Usage: %s [--tcp-host HOST] [--tcp-port PORT] [--channel RFCOMM_CHANNEL] [--service-name NAME]\n", programName);
}

static void HandleSignal(int signalNumber) {
    (void)signalNumber;
    gKeepRunning = 0;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *tcpHost = @"127.0.0.1";
        uint16_t tcpPort = 35963;
        uint8_t preferredChannel = 12;
        NSString *serviceName = kDefaultServiceName;

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--tcp-host"] && i + 1 < argc) {
                tcpHost = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--tcp-port"] && i + 1 < argc) {
                tcpPort = (uint16_t)strtoul(argv[++i], NULL, 10);
            } else if ([arg isEqualToString:@"--channel"] && i + 1 < argc) {
                preferredChannel = (uint8_t)strtoul(argv[++i], NULL, 10);
            } else if ([arg isEqualToString:@"--service-name"] && i + 1 < argc) {
                serviceName = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--help"]) {
                PrintUsage(argv[0]);
                return 0;
            } else {
                PrintUsage(argv[0]);
                return 1;
            }
        }

        RFCOMMVPCDBridge *bridge = [[RFCOMMVPCDBridge alloc] initWithHost:tcpHost
                                                                      port:tcpPort
                                                                   channel:preferredChannel
                                                               serviceName:serviceName];
        NSError *error = nil;
        if (![bridge start:&error]) {
            fprintf(stderr, "Failed to start bridge: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        signal(SIGPIPE, SIG_IGN);
        signal(SIGINT, HandleSignal);
        signal(SIGTERM, HandleSignal);
        while (gKeepRunning) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            }
        }
        [bridge stop];
    }
    return 0;
}
