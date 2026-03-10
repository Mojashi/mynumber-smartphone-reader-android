package com.vsmartcard.remotesmartcardreader.app;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

interface VPCDConnection {
    InputStream getInputStream() throws IOException;
    OutputStream getOutputStream() throws IOException;
    String describePeer();
    void close() throws IOException;
}
