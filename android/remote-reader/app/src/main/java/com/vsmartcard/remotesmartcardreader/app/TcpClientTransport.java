package com.vsmartcard.remotesmartcardreader.app;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;

class TcpClientTransport implements VPCDTransport {
    private final String hostname;
    private final int port;

    TcpClientTransport(String hostname, int port) {
        this.hostname = hostname;
        this.port = port;
    }

    @Override
    public VPCDConnection open() throws IOException {
        final Socket socket = new Socket(InetAddress.getByName(hostname), port);
        socket.setTcpNoDelay(true);
        return new SocketConnection(socket, hostname + ":" + port);
    }

    @Override
    public boolean isReusable() {
        return false;
    }

    @Override
    public String describeEndpoint() {
        return hostname + ":" + port;
    }

    @Override
    public void close() {
    }

    private static class SocketConnection implements VPCDConnection {
        private final Socket socket;
        private final String description;

        SocketConnection(Socket socket, String description) {
            this.socket = socket;
            this.description = description;
        }

        @Override
        public InputStream getInputStream() throws IOException {
            return socket.getInputStream();
        }

        @Override
        public OutputStream getOutputStream() throws IOException {
            return socket.getOutputStream();
        }

        @Override
        public String describePeer() {
            return description;
        }

        @Override
        public void close() throws IOException {
            socket.close();
        }
    }
}
