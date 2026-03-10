#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

#include <dispatch/dispatch.h>
#include <netdb.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <uuid/uuid.h>

static NSString * const kDefaultServiceUUID = @"00001101-0000-1000-8000-00805f9b34fb";
static NSString * const kDefaultServiceName = @"MyNumber Reader";
static volatile sig_atomic_t gKeepRunning = 1;

static void HandleSignal(int signalNumber) {
    (void)signalNumber;
    gKeepRunning = 0;
}

static NSString *NormalizeBluetoothAddress(NSString *address) {
    return [[address uppercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@":"];
}

static NSData *UUIDDataFromString(NSString *uuidString) {
    uuid_t bytes;
    if (uuid_parse(uuidString.UTF8String, bytes) != 0) {
        return nil;
    }
    return [NSData dataWithBytes:bytes length:sizeof(uuid_t)];
}

static NSString *StringFromIOReturn(IOReturn status) {
    return [NSString stringWithFormat:@"0x%08x", status];
}

static void PrintPairedDevices(void) {
    NSArray *devices = [IOBluetoothDevice pairedDevices];
    if (devices.count == 0) {
        printf("No paired Bluetooth devices found.\n");
        return;
    }

    for (IOBluetoothDevice *device in devices) {
        printf("%s\t%s\n",
               device.addressString.UTF8String,
               device.nameOrAddress.UTF8String);
    }
}

@interface RFCOMMClientBridge : NSObject <IOBluetoothRFCOMMChannelDelegate>

@property(nonatomic, copy) NSString *deviceAddress;
@property(nonatomic, copy) NSString *deviceName;
@property(nonatomic, copy) NSString *serviceUUID;
@property(nonatomic, copy) NSString *tcpHost;
@property(nonatomic) uint16_t tcpPort;
@property(nonatomic) NSTimeInterval retryInterval;
@property(nonatomic, retain) IOBluetoothDevice *device;
@property(nonatomic, retain) IOBluetoothRFCOMMChannel *channel;
@property(nonatomic) int tcpSocket;
@property(nonatomic) dispatch_source_t tcpReadSource;
@property(nonatomic) dispatch_queue_t ioQueue;
- (instancetype)initWithDeviceAddress:(NSString *)deviceAddress
                           deviceName:(NSString *)deviceName
                          serviceUUID:(NSString *)serviceUUID
                              tcpHost:(NSString *)tcpHost
                              tcpPort:(uint16_t)tcpPort
                        retryInterval:(NSTimeInterval)retryInterval;
- (BOOL)runOnce:(NSError **)error;
- (void)stop;

@end

@implementation RFCOMMClientBridge

- (instancetype)initWithDeviceAddress:(NSString *)deviceAddress
                           deviceName:(NSString *)deviceName
                          serviceUUID:(NSString *)serviceUUID
                              tcpHost:(NSString *)tcpHost
                              tcpPort:(uint16_t)tcpPort
                        retryInterval:(NSTimeInterval)retryInterval {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _deviceAddress = [deviceAddress copy];
    _deviceName = [deviceName copy];
    _serviceUUID = [serviceUUID copy];
    _tcpHost = [tcpHost copy];
    _tcpPort = tcpPort;
    _retryInterval = retryInterval;
    _tcpSocket = -1;
    _ioQueue = dispatch_queue_create("jp.mojashi.mynumber-bridge.rfcomm-client", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)runOnce:(NSError **)error {
    if (![self connectBluetooth:error]) {
        return NO;
    }
    if (![self waitForTCP:error]) {
        [self closeActiveBridge];
        return NO;
    }
    [self startTCPPump];

    NSLog(@"Bluetooth bridge is active.");
    while (gKeepRunning && self.channel != nil && self.tcpSocket >= 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        }
    }
    return YES;
}

- (void)stop {
    [self closeActiveBridge];
    if (self.device != nil && self.device.isConnected) {
        [self.device closeConnection];
    }
    self.device = nil;
}

- (BOOL)waitForTCP:(NSError **)error {
    while (gKeepRunning) {
        NSError *connectError = nil;
        int socketFD = [self connectTCP:&connectError];
        if (socketFD >= 0) {
            self.tcpSocket = socketFD;
            NSLog(@"Connected to VPCD on %@:%u", self.tcpHost, self.tcpPort);
            return YES;
        }

        NSLog(@"Waiting for VPCD on %@:%u: %@", self.tcpHost, self.tcpPort, connectError.localizedDescription);
        [NSThread sleepForTimeInterval:self.retryInterval];
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:EINTR
                                 userInfo:@{NSLocalizedDescriptionKey: @"Interrupted while waiting for VPCD."}];
    }
    return NO;
}

- (BOOL)connectBluetooth:(NSError **)error {
    self.device = [self resolveDevice:error];
    if (self.device == nil) {
        return NO;
    }

    if (!self.device.isConnected) {
        IOReturn status = [self.device openConnection];
        if (status != kIOReturnSuccess) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:status
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Failed to open Bluetooth connection to %@ (%@).",
                                                         self.device.nameOrAddress, StringFromIOReturn(status)]}];
            }
            return NO;
        }
    }

    IOBluetoothSDPServiceRecord *serviceRecord = [self queryServiceRecord:error];
    if (serviceRecord == nil) {
        return NO;
    }

    BluetoothRFCOMMChannelID channelID = 0;
    IOReturn channelStatus = [serviceRecord getRFCOMMChannelID:&channelID];
    if (channelStatus != kIOReturnSuccess || channelID == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:channelStatus
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Service %@ does not expose an RFCOMM channel.",
                                                     self.serviceUUID]}];
        }
        return NO;
    }

    IOBluetoothRFCOMMChannel *channel = nil;
    IOReturn openStatus = [self.device openRFCOMMChannelSync:&channel withChannelID:channelID delegate:self];
    if (openStatus != kIOReturnSuccess || channel == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:openStatus
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to open RFCOMM channel %u on %@ (%@).",
                                                     channelID, self.device.nameOrAddress, StringFromIOReturn(openStatus)]}];
        }
        return NO;
    }

    self.channel = channel;
    [self.channel setDelegate:self];
    NSLog(@"Connected to %@ over RFCOMM channel %u", self.device.nameOrAddress, channelID);
    return YES;
}

- (IOBluetoothDevice *)resolveDevice:(NSError **)error {
    if (self.deviceAddress != nil && self.deviceAddress.length > 0) {
        return [IOBluetoothDevice deviceWithAddressString:NormalizeBluetoothAddress(self.deviceAddress)];
    }

    NSArray *devices = [IOBluetoothDevice pairedDevices];
    NSMutableArray *matches = [NSMutableArray array];
    for (IOBluetoothDevice *candidate in devices) {
        if (self.deviceName != nil && self.deviceName.length > 0) {
            NSString *name = candidate.nameOrAddress ?: @"";
            if ([name rangeOfString:self.deviceName options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:candidate];
            }
            continue;
        }

        NSString *name = candidate.nameOrAddress ?: @"";
        if ([name rangeOfString:@"Pixel" options:NSCaseInsensitiveSearch].location != NSNotFound
                || [name rangeOfString:@"Android" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [matches addObject:candidate];
        }
    }

    if (matches.count == 1) {
        return matches.firstObject;
    }

    if (error != NULL) {
        NSString *message;
        if (matches.count == 0) {
            message = @"Could not determine which paired Android device to use. Pass --device-address or --device-name.";
        } else {
            message = @"Multiple paired Android-like devices matched. Pass --device-address or --device-name.";
        }
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:ENOENT
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return nil;
}

- (IOBluetoothSDPServiceRecord *)queryServiceRecord:(NSError **)error {
    NSData *uuidData = UUIDDataFromString(self.serviceUUID);
    if (uuidData == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EINVAL
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid Bluetooth service UUID."}];
        }
        return nil;
    }

    IOBluetoothSDPUUID *uuid = [IOBluetoothSDPUUID uuidWithData:uuidData];
    if (uuid == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EINVAL
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to build Bluetooth SDP UUID."}];
        }
        return nil;
    }

    NSDate *lastServicesUpdate = [self.device getLastServicesUpdate];
    IOReturn status = [self.device performSDPQuery:nil uuids:@[uuid]];
    if (status != kIOReturnSuccess) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to start SDP query on %@ (%@).",
                                                     self.device.nameOrAddress, StringFromIOReturn(status)]}];
        }
        return nil;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (gKeepRunning && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

        IOBluetoothSDPServiceRecord *record = [self.device getServiceRecordForUUID:uuid];
        if (record != nil) {
            return record;
        }

        NSDate *currentServicesUpdate = [self.device getLastServicesUpdate];
        if (lastServicesUpdate != nil && currentServicesUpdate != nil
                && [currentServicesUpdate compare:lastServicesUpdate] == NSOrderedDescending) {
            break;
        }
    }

    IOBluetoothSDPServiceRecord *record = [self.device getServiceRecordForUUID:uuid];
    if (record == nil && error != NULL) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:ENOENT
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Service %@ is not currently advertised by %@. Touch the My Number card so the phone starts listening.",
                                                 self.serviceUUID, self.device.nameOrAddress]}];
    }
    return record;
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
                                     code:errno
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Could not connect to %@:%u", self.tcpHost, self.tcpPort]}];
    }
    return socketFD;
}

- (void)startTCPPump {
    if (self.tcpSocket < 0 || self.channel == nil) {
        return;
    }

    self.tcpReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)self.tcpSocket, 0, self.ioQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.tcpReadSource, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        uint8_t buffer[4096];
        ssize_t count = recv(strongSelf.tcpSocket, buffer, sizeof(buffer), 0);
        if (count <= 0) {
            NSLog(@"VPCD side closed.");
            [strongSelf closeActiveBridge];
            return;
        }

        UInt16 mtu = strongSelf.channel.getMTU;
        if (mtu == 0) {
            mtu = 127;
        }

        size_t offset = 0;
        while (offset < (size_t)count) {
            UInt16 chunkLength = (UInt16)MIN((size_t)mtu, (size_t)count - offset);
            IOReturn status = [strongSelf.channel writeSync:(void *)(buffer + offset) length:chunkLength];
            if (status != kIOReturnSuccess) {
                NSLog(@"RFCOMM write failed: %@", StringFromIOReturn(status));
                [strongSelf closeActiveBridge];
                return;
            }
            offset += chunkLength;
        }
    });
    dispatch_source_set_cancel_handler(self.tcpReadSource, ^{
    });
    dispatch_resume(self.tcpReadSource);
}

- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength {
    (void)rfcommChannel;
    if (self.tcpSocket < 0 || dataLength == 0) {
        return;
    }

    const uint8_t *buffer = dataPointer;
    size_t offset = 0;
    while (offset < dataLength) {
        ssize_t written = send(self.tcpSocket, buffer + offset, dataLength - offset, 0);
        if (written <= 0) {
            NSLog(@"TCP write failed.");
            [self closeActiveBridge];
            return;
        }
        offset += (size_t)written;
    }
}

- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)rfcommChannel status:(IOReturn)error {
    if (error != kIOReturnSuccess) {
        NSLog(@"RFCOMM open failed for %@: %@", rfcommChannel.getDevice.nameOrAddress, StringFromIOReturn(error));
        [self closeActiveBridge];
    }
}

- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)rfcommChannel {
    NSLog(@"Bluetooth client disconnected: %@", rfcommChannel.getDevice.nameOrAddress);
    [self closeActiveBridge];
}

- (void)closeActiveBridge {
    if (self.tcpReadSource != nil) {
        dispatch_source_cancel(self.tcpReadSource);
        self.tcpReadSource = nil;
    }
    if (self.tcpSocket >= 0) {
        close(self.tcpSocket);
        self.tcpSocket = -1;
    }
    if (self.channel != nil) {
        [self.channel closeChannel];
        self.channel = nil;
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        signal(SIGINT, HandleSignal);
        signal(SIGTERM, HandleSignal);

        NSString *deviceAddress = nil;
        NSString *deviceName = nil;
        NSString *serviceUUID = kDefaultServiceUUID;
        NSString *tcpHost = @"127.0.0.1";
        uint16_t tcpPort = 35963;
        double retryInterval = 1.0;
        BOOL listOnly = NO;

        for (int i = 1; i < argc; i++) {
            NSString *argument = [NSString stringWithUTF8String:argv[i]];
            if ([argument isEqualToString:@"--device-address"] && i + 1 < argc) {
                deviceAddress = [NSString stringWithUTF8String:argv[++i]];
            } else if ([argument isEqualToString:@"--device-name"] && i + 1 < argc) {
                deviceName = [NSString stringWithUTF8String:argv[++i]];
            } else if ([argument isEqualToString:@"--service-uuid"] && i + 1 < argc) {
                serviceUUID = [NSString stringWithUTF8String:argv[++i]];
            } else if ([argument isEqualToString:@"--tcp-host"] && i + 1 < argc) {
                tcpHost = [NSString stringWithUTF8String:argv[++i]];
            } else if ([argument isEqualToString:@"--tcp-port"] && i + 1 < argc) {
                tcpPort = (uint16_t)strtoul(argv[++i], NULL, 10);
            } else if ([argument isEqualToString:@"--retry-interval"] && i + 1 < argc) {
                retryInterval = strtod(argv[++i], NULL);
            } else if ([argument isEqualToString:@"--list-devices"]) {
                listOnly = YES;
            } else {
                fprintf(stderr, "usage: %s [--device-address AA:BB:CC:DD:EE:FF] [--device-name NAME] [--service-uuid UUID] [--tcp-host HOST] [--tcp-port PORT] [--retry-interval SECONDS] [--list-devices]\n", argv[0]);
                return 2;
            }
        }

        if (listOnly) {
            PrintPairedDevices();
            return 0;
        }

        NSLog(@"RFCOMM client helper starting.");
        NSLog(@"Target device address: %@", deviceAddress ?: @"(auto)");
        NSLog(@"Target device name: %@", deviceName ?: @"(auto)");
        NSLog(@"Target service: %@ (%@)", kDefaultServiceName, serviceUUID);
        NSLog(@"Forward target: %@:%u", tcpHost, tcpPort);

        RFCOMMClientBridge *bridge = [[RFCOMMClientBridge alloc] initWithDeviceAddress:deviceAddress
                                                                             deviceName:deviceName
                                                                            serviceUUID:serviceUUID
                                                                                tcpHost:tcpHost
                                                                                tcpPort:tcpPort
                                                                          retryInterval:retryInterval];

        while (gKeepRunning) {
            NSError *error = nil;
            [bridge runOnce:&error];
            [bridge stop];
            if (!gKeepRunning) {
                break;
            }
            if (error != nil) {
                NSLog(@"%@", error.localizedDescription);
            }
            [NSThread sleepForTimeInterval:retryInterval];
        }

        NSLog(@"Stopping RFCOMM client helper.");
    }
    return 0;
}
