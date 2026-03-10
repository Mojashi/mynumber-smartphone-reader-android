package com.vsmartcard.remotesmartcardreader.app;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.util.Enumeration;
import java.util.LinkedList;
import java.util.List;

class TcpServerTransport implements VPCDTransport {
    private final int port;
    private ServerSocket serverSocket;
    private String description;

    TcpServerTransport(int port) {
        this.port = port;
    }

    @Override
    public VPCDConnection open() throws IOException {
        ensureServerSocket();

        Socket socket = null;
        while (socket == null) {
            serverSocket.setSoTimeout(1000);
            try {
                socket = serverSocket.accept();
                socket.setTcpNoDelay(true);
            } catch (SocketTimeoutException ignored) {
            }
        }
        serverSocket.setSoTimeout(0);
        return new SocketConnection(socket);
    }

    @Override
    public boolean isReusable() {
        return true;
    }

    @Override
    public String describeEndpoint() {
        return description;
    }

    @Override
    public void close() throws IOException {
        if (serverSocket != null) {
            serverSocket.close();
            serverSocket = null;
        }
    }

    private void ensureServerSocket() throws IOException {
        if (serverSocket != null) {
            return;
        }
        serverSocket = new ServerSocket(port);
        final List<String> ifaceAddresses = new LinkedList<>();
        final Enumeration<NetworkInterface> ifaces = NetworkInterface.getNetworkInterfaces();
        while (ifaces.hasMoreElements()) {
            final NetworkInterface iface = ifaces.nextElement();
            if (!iface.isUp() || iface.isLoopback() || iface.isVirtual()) {
                continue;
            }
            for (InterfaceAddress addr : iface.getInterfaceAddresses()) {
                final InetAddress inetAddr = addr.getAddress();
                ifaceAddresses.add(inetAddr.getHostAddress());
            }
        }
        description = "port " + port + ". Local addresses: " + join(", ", ifaceAddresses);
    }

    private static String join(String separator, List<String> input) {
        if (input == null || input.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < input.size(); i++) {
            sb.append(input.get(i));
            if (i != input.size() - 1) {
                sb.append(separator);
            }
        }
        return sb.toString();
    }

    private static class SocketConnection implements VPCDConnection {
        private final Socket socket;

        SocketConnection(Socket socket) {
            this.socket = socket;
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
            return socket.getInetAddress().toString();
        }

        @Override
        public void close() throws IOException {
            socket.close();
        }
    }
}
