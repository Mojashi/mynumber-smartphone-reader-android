package com.vsmartcard.remotesmartcardreader.app;

import java.io.IOException;

interface VPCDTransport {
    VPCDConnection open() throws IOException;
    boolean isReusable();
    String describeEndpoint();
    void close() throws IOException;
}
