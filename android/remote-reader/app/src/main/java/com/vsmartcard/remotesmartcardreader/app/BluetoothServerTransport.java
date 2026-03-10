package com.vsmartcard.remotesmartcardreader.app;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;

import java.io.IOException;
import java.util.UUID;

class BluetoothServerTransport implements VPCDTransport {
    static final String DEFAULT_SERVICE_NAME = "MyNumber Reader";
    static final String DEFAULT_SERVICE_UUID = "00001101-0000-1000-8000-00805f9b34fb";

    private final String serviceName;
    private final UUID serviceUuid;
    private BluetoothServerSocket serverSocket;

    BluetoothServerTransport(String serviceName, String serviceUuid) {
        this.serviceName = serviceName;
        this.serviceUuid = UUID.fromString(serviceUuid);
    }

    @Override
    public VPCDConnection open() throws IOException {
        ensureServerSocket();
        final BluetoothSocket socket = serverSocket.accept();
        return new BluetoothSocketConnection(socket);
    }

    @Override
    public boolean isReusable() {
        return true;
    }

    @Override
    public String describeEndpoint() {
        return serviceName + " [" + serviceUuid + "]";
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

        final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            throw new IOException("Bluetooth is not available on this device.");
        }
        if (!adapter.isEnabled()) {
            throw new IOException("Bluetooth is disabled.");
        }

        adapter.cancelDiscovery();
        serverSocket = adapter.listenUsingRfcommWithServiceRecord(serviceName, serviceUuid);
    }
}
